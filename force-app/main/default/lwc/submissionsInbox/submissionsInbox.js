import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSubmissionEmails from '@salesforce/apex/SubmissionsInboxController.getSubmissionEmails';
import processEmail from '@salesforce/apex/ProcessSubmissionEmailAction.processEmail';

const COLUMNS = [
    {
        label: 'From',
        fieldName: 'fromDisplay',
        type: 'text',
        wrapText: false,
        cellAttributes: { iconName: 'utility:user' }
    },
    {
        label: 'Subject',
        fieldName: 'Subject__c',
        type: 'text',
        wrapText: false,
        sortable: true
    },
    {
        label: 'Received',
        fieldName: 'Received_Date__c',
        type: 'date',
        sortable: true,
        typeAttributes: {
            month: '2-digit',
            day:   '2-digit',
            year:  'numeric',
            hour:  '2-digit',
            minute: '2-digit'
        }
    },
    {
        label: 'Attachments',
        fieldName: 'Attachment_Count__c',
        type: 'number',
        sortable: true,
        initialWidth: 120,
        cellAttributes: { alignment: 'center' }
    },
    {
        label: 'Status',
        fieldName: 'Status__c',
        type: 'text',
        sortable: true,
        initialWidth: 130
    },
    {
        type: 'button',
        initialWidth: 210,
        typeAttributes: {
            label: 'Process with Agentforce',
            name: 'process',
            variant: 'brand',
            iconName: 'utility:einstein',
            iconPosition: 'left',
            disabled: { fieldName: 'isProcessed' }
        }
    }
];

export default class SubmissionsInbox extends NavigationMixin(LightningElement) {
    columns      = COLUMNS;
    emails       = [];
    isLoading    = true;
    isProcessing = false;
    hasError     = false;
    _wiredResult;

    @wire(getSubmissionEmails)
    wiredEmails(result) {
        this._wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.emails = data.map(record => ({
                ...record,
                fromDisplay: record.From_Name__c
                    ? `${record.From_Name__c} <${record.From_Email__c ?? ''}>`
                    : (record.From_Email__c ?? '—'),
                isProcessed: record.Status__c === 'Processed'
            }));
            this.isLoading = false;
            this.hasError  = false;
        } else if (error) {
            console.error('SubmissionsInbox error:', JSON.stringify(error));
            this.isLoading = false;
            this.hasError  = true;
        }
    }

    get hasEmails() {
        return this.emails?.length > 0;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this._wiredResult);
    }

    handleRowAction(event) {
        const { action, row } = event.detail;

        if (action.name === 'process') {
            this._processEmail(row.Id);
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: row.Id, actionName: 'view' }
            });
        }
    }

    _processEmail(emailId) {
        this.isProcessing = true;

        processEmail({ submissionEmailId: emailId })
            .then(submissionId => {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Submission Created',
                    message: 'Email processed and submission record created.',
                    variant: 'success'
                }));
                refreshApex(this._wiredResult);
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId:      submissionId,
                        objectApiName: 'Submission__c',
                        actionName:    'view'
                    }
                });
            })
            .catch(error => {
                const msg = error?.body?.message ?? 'An unexpected error occurred.';
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Processing Failed',
                    message: msg,
                    variant: 'error',
                    mode:    'sticky'
                }));
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }
}
