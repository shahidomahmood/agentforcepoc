import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getSubmissionEmails from '@salesforce/apex/SubmissionsInboxController.getSubmissionEmails';

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
        initialWidth: 140,
        typeAttributes: {
            label: 'Process',
            name: 'process',
            variant: 'brand',
            iconName: 'utility:forward',
            iconPosition: 'right'
        }
    }
];

export default class SubmissionsInbox extends NavigationMixin(LightningElement) {
    columns   = COLUMNS;
    emails    = [];
    isLoading = true;
    hasError  = false;
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
                    : (record.From_Email__c ?? '—')
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
        const row = event.detail.row;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:   row.Id,
                actionName: 'view'
            }
        });
    }
}