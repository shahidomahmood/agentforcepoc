import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

// Requires US-009, US-010, US-011 to be deployed before this component is active
import extractData        from '@salesforce/apex/SubmissionExtractionAction.extractData';
import validateSubmission from '@salesforce/apex/SubmissionValidationAction.validateSubmission';
import evaluateRisk       from '@salesforce/apex/RiskSignalService.evaluateRisk';

import EXTRACTION_STATUS   from '@salesforce/schema/Submission__c.Extraction_Status__c';
import COMPLETENESS_STATUS from '@salesforce/schema/Submission__c.Completeness_Status__c';
import RISK_SCORE          from '@salesforce/schema/Submission__c.Risk_Score__c';

const FIELDS = [EXTRACTION_STATUS, COMPLETENESS_STATUS, RISK_SCORE];

const CIRCLE = {
    pending:  'step-circle step-circle_pending',
    current:  'step-circle step-circle_current',
    complete: 'step-circle step-circle_complete',
    error:    'step-circle step-circle_error',
};
const TITLE = {
    pending:  'step-title step-title_pending',
    current:  'step-title step-title_current',
    complete: 'step-title step-title_complete',
    error:    'step-title step-title_error',
};
const BADGE = {
    pending:  'step-badge step-badge_pending',
    current:  'step-badge step-badge_current',
    complete: 'step-badge step-badge_complete',
    error:    'step-badge step-badge_error',
};

export default class SubmissionProgress extends LightningElement {
    @api recordId;
    @track isLoadingExtract  = false;
    @track isLoadingValidate = false;
    @track isLoadingRisk     = false;

    _wiredRecord;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord(result) {
        this._wiredRecord = result;
    }

    // ── Raw field values ────────────────────────────────────────────────────
    get extractionStatus()   { return getFieldValue(this._wiredRecord?.data, EXTRACTION_STATUS);   }
    get completenessStatus() { return getFieldValue(this._wiredRecord?.data, COMPLETENESS_STATUS); }
    get riskScore()          { return getFieldValue(this._wiredRecord?.data, RISK_SCORE);          }

    // ── Step 1: Extract Data ────────────────────────────────────────────────
    get step1Done()       { return this.extractionStatus === 'Completed'; }
    get step1Error()      { return this.extractionStatus === 'Failed'; }
    get _step1State()     { return this.step1Done ? 'complete' : this.step1Error ? 'error' : 'current'; }
    get step1CircleCls()  { return CIRCLE[this._step1State]; }
    get step1TitleCls()   { return TITLE[this._step1State]; }
    get step1BadgeCls()   { return BADGE[this._step1State]; }
    get step1Num()        { return this.step1Done ? '✓' : this.step1Error ? '✕' : '1'; }
    get step1StatusLabel() {
        if (this.step1Done)  return 'Completed';
        if (this.step1Error) return 'Failed — click to retry';
        if (this.extractionStatus === 'In Progress') return 'In Progress';
        return 'Not Started';
    }
    get step1BtnLabel()   { return this.step1Done ? 'Re-extract' : this.step1Error ? 'Retry Extraction' : 'Extract with Agentforce'; }
    get step1BtnVariant() { return this._step1State === 'current' ? 'brand' : 'neutral'; }

    // ── Step 2: Check Missing Info ──────────────────────────────────────────
    get step2Done()       { return !!this.completenessStatus; }
    get step2Locked()     { return !this.step1Done; }
    get _step2State()     { return this.step2Done ? 'complete' : this.step2Locked ? 'pending' : 'current'; }
    get step2CircleCls()  { return CIRCLE[this._step2State]; }
    get step2TitleCls()   { return TITLE[this._step2State]; }
    get step2BadgeCls()   { return BADGE[this._step2State]; }
    get step2Num()        { return this.step2Done ? '✓' : '2'; }
    get step2StatusLabel() {
        if (this.step2Locked) return 'Complete step 1 first';
        if (this.step2Done)   return this.completenessStatus;
        return 'Not Started';
    }
    get step2BtnVariant() { return this._step2State === 'current' ? 'brand' : 'neutral'; }

    // ── Step 3: Evaluate Risk ───────────────────────────────────────────────
    get step3Done()       { return this.riskScore != null; }
    get step3Locked()     { return !this.step1Done || !this.step2Done; }
    get _step3State()     { return this.step3Done ? 'complete' : this.step3Locked ? 'pending' : 'current'; }
    get step3CircleCls()  { return CIRCLE[this._step3State]; }
    get step3TitleCls()   { return TITLE[this._step3State]; }
    get step3BadgeCls()   { return BADGE[this._step3State]; }
    get step3Num()        { return this.step3Done ? '✓' : '3'; }
    get step3StatusLabel() {
        if (this.step3Locked) return 'Complete step 2 first';
        if (this.step3Done)   return 'Completed';
        return 'Not Started';
    }
    get step3BtnVariant() { return this._step3State === 'current' ? 'brand' : 'neutral'; }

    // ── Step 4: Ready for Review ────────────────────────────────────────────
    get step4Done()       { return this.step1Done && this.step2Done && this.step3Done; }
    get _step4State()     { return this.step4Done ? 'complete' : 'pending'; }
    get step4CircleCls()  { return CIRCLE[this._step4State]; }
    get step4TitleCls()   { return TITLE[this._step4State]; }
    get step4BadgeCls()   { return BADGE[this._step4State]; }
    get step4Num()        { return this.step4Done ? '✓' : '4'; }
    get step4StatusLabel() { return this.step4Done ? 'Ready' : 'Waiting on steps 1–3'; }

    // ── Connectors (green once the preceding step is complete) ──────────────
    get conn12() { return 'connector' + (this.step1Done ? ' connector_complete' : ''); }
    get conn23() { return 'connector' + (this.step2Done ? ' connector_complete' : ''); }
    get conn34() { return 'connector' + (this.step3Done ? ' connector_complete' : ''); }

    // ── Action handlers ─────────────────────────────────────────────────────
    handleExtract() {
        this.isLoadingExtract = true;
        extractData({ submissionId: this.recordId })
            .then(() => refreshApex(this._wiredRecord))
            .then(() => this._toast('Extraction Complete', 'Data extracted from submission documents.', 'success'))
            .catch(e  => this._toast('Extraction Failed', e?.body?.message ?? 'Unexpected error.', 'error', 'sticky'))
            .finally(() => { this.isLoadingExtract = false; });
    }

    handleValidate() {
        this.isLoadingValidate = true;
        validateSubmission({ submissionId: this.recordId })
            .then(count => {
                const msg = count === 0
                    ? 'Submission is complete — no missing items.'
                    : `${count} missing item(s) found. Email draft generated.`;
                this._toast(count === 0 ? 'Complete' : 'Missing Items Found', msg, count === 0 ? 'success' : 'warning');
                return refreshApex(this._wiredRecord);
            })
            .catch(e => this._toast('Validation Failed', e?.body?.message ?? 'Unexpected error.', 'error', 'sticky'))
            .finally(() => { this.isLoadingValidate = false; });
    }

    handleRisk() {
        this.isLoadingRisk = true;
        evaluateRisk({ submissionId: this.recordId })
            .then(() => refreshApex(this._wiredRecord))
            .then(() => this._toast('Risk Evaluation Complete', 'Risk signals and scores updated.', 'success'))
            .catch(e  => this._toast('Evaluation Failed', e?.body?.message ?? 'Unexpected error.', 'error', 'sticky'))
            .finally(() => { this.isLoadingRisk = false; });
    }

    _toast(title, message, variant, mode = 'dismissible') {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode }));
    }
}
