import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getSignals from '@salesforce/apex/RiskSignalService.getSignals';
import RISK_SCORE_FIELD from '@salesforce/schema/Submission__c.Risk_Score__c';
import APPETITE_SCORE_FIELD from '@salesforce/schema/Submission__c.Appetite_Score__c';
import REVIEW_PRIORITY_FIELD from '@salesforce/schema/Submission__c.Review_Priority__c';
import RISK_SUMMARY_FIELD from '@salesforce/schema/Submission__c.Risk_Summary__c';

const FIELDS = [RISK_SCORE_FIELD, APPETITE_SCORE_FIELD, REVIEW_PRIORITY_FIELD, RISK_SUMMARY_FIELD];

const SEVERITY_CSS = {
    High:     'signal-item signal-high slds-var-m-bottom_x-small slds-var-p-around_small',
    Medium:   'signal-item signal-medium slds-var-m-bottom_x-small slds-var-p-around_small',
    Low:      'signal-item signal-low slds-var-m-bottom_x-small slds-var-p-around_small',
    Positive: 'signal-item signal-positive slds-var-m-bottom_x-small slds-var-p-around_small'
};

const BADGE_CSS = {
    High:     'slds-badge badge-high',
    Medium:   'slds-badge badge-medium',
    Low:      'slds-badge badge-low',
    Positive: 'slds-badge badge-positive'
};

export default class SubmissionRiskSignals extends LightningElement {
    @api recordId;

    _wiredRecord;
    _wiredSignals;
    _prevRiskScore = undefined;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord(result) {
        this._wiredRecord = result;
        if (result.data) {
            const score = getFieldValue(result.data, RISK_SCORE_FIELD);
            if (score !== this._prevRiskScore) {
                this._prevRiskScore = score;
                if (this._wiredSignals) {
                    refreshApex(this._wiredSignals);
                }
            }
        }
    }

    @wire(getSignals, { submissionId: '$recordId' })
    wiredSignals(result) {
        this._wiredSignals = result;
    }

    get riskScore() {
        return getFieldValue(this._wiredRecord?.data, RISK_SCORE_FIELD);
    }

    get appetiteScore() {
        return getFieldValue(this._wiredRecord?.data, APPETITE_SCORE_FIELD);
    }

    get reviewPriority() {
        return getFieldValue(this._wiredRecord?.data, REVIEW_PRIORITY_FIELD);
    }

    get riskSummary() {
        return getFieldValue(this._wiredRecord?.data, RISK_SUMMARY_FIELD);
    }

    get hasScores() {
        return this.riskScore != null || this.appetiteScore != null;
    }

    get signals() {
        if (!this._wiredSignals?.data) return [];
        return this._wiredSignals.data.map(s => ({
            ...s,
            cssClass:   SEVERITY_CSS[s.Severity__c]  ?? SEVERITY_CSS.Low,
            badgeClass: BADGE_CSS[s.Severity__c]     ?? BADGE_CSS.Low
        }));
    }

    get hasSignals() {
        return this.signals.length > 0;
    }

    get hasContent() {
        return this.hasScores || this.hasSignals || this.riskSummary;
    }

    get priorityTileClass() {
        const p = this.reviewPriority;
        if (p === 'High Priority')   return 'score-tile priority-high';
        if (p === 'Standard Review') return 'score-tile priority-standard';
        if (p === 'Low Priority')    return 'score-tile priority-low';
        return 'score-tile';
    }

}
