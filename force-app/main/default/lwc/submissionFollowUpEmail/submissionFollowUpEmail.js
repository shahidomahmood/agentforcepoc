import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import sendFollowUpEmail from '@salesforce/apex/SubmissionValidationAction.sendFollowUpEmail';
import saveDraft from '@salesforce/apex/SubmissionValidationAction.saveDraft';

import FOLLOW_UP_DRAFT_FIELD   from '@salesforce/schema/Submission__c.Follow_Up_Email_Draft__c';
import COMPLETENESS_FIELD      from '@salesforce/schema/Submission__c.Completeness_Status__c';
import BROKER_EMAIL_FIELD      from '@salesforce/schema/Submission__c.Submission_Email__r.From_Email__c';
import BROKER_NAME_FIELD       from '@salesforce/schema/Submission__c.Submission_Email__r.From_Name__c';

const FIELDS = [FOLLOW_UP_DRAFT_FIELD, COMPLETENESS_FIELD, BROKER_EMAIL_FIELD, BROKER_NAME_FIELD];

export default class SubmissionFollowUpEmail extends LightningElement {
    @api recordId;
    @track emailDraft = '';
    isBusy        = false;
    busyMessage   = '';
    _wiredRecord;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord(result) {
        this._wiredRecord = result;
        if (result.data) {
            const draft = getFieldValue(result.data, FOLLOW_UP_DRAFT_FIELD);
            this.emailDraft = draft ?? '';
        }
    }

    get completenessStatus() {
        return this._wiredRecord?.data
            ? getFieldValue(this._wiredRecord.data, COMPLETENESS_FIELD)
            : null;
    }

    get brokerEmail() {
        return this._wiredRecord?.data
            ? getFieldValue(this._wiredRecord.data, BROKER_EMAIL_FIELD)
            : '';
    }

    get hasDraft() {
        return String(this.emailDraft ?? '').trim().length > 0;
    }

    get statusBadgeClass() {
        const base = 'slds-badge slds-var-m-bottom_small ';
        return this.completenessStatus === 'Ready for Review'
            ? base + 'slds-badge_lightest'
            : base + 'slds-theme_warning';
    }

    handleDraftChange(event) {
        this.emailDraft = event.target.value;
    }

    handleSaveDraft() {
        this.isBusy      = true;
        this.busyMessage = 'Saving…';

        saveDraft({ submissionId: this.recordId, emailBody: this.emailDraft })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Saved', message: 'Draft saved.', variant: 'success'
                }));
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Save Failed',
                    message: error?.body?.message ?? 'An unexpected error occurred.',
                    variant: 'error'
                }));
            })
            .finally(() => { this.isBusy = false; });
    }

    handleSend() {
        if (!this.brokerEmail) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'No Recipient', message: 'No broker email address found on this submission.', variant: 'error'
            }));
            return;
        }

        this.isBusy      = true;
        this.busyMessage = 'Sending email…';

        sendFollowUpEmail({ submissionId: this.recordId, emailBody: this.emailDraft })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Email Sent',
                    message: 'Follow-up email sent to ' + this.brokerEmail + '.',
                    variant: 'success'
                }));
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Send Failed',
                    message: error?.body?.message ?? 'An unexpected error occurred.',
                    variant: 'error',
                    mode:    'sticky'
                }));
            })
            .finally(() => { this.isBusy = false; });
    }
}
