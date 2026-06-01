import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import extractData from '@salesforce/apex/SubmissionExtractionAction.extractData';

export default class SubmissionExtractButton extends LightningElement {
    @api recordId;
    isLoading = false;

    handleExtract() {
        this.isLoading = true;

        extractData({ submissionId: this.recordId })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Extraction Complete',
                    message: 'Agentforce successfully extracted data from the submission documents.',
                    variant: 'success'
                }));
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(error => {
                const msg = error?.body?.message ?? 'An unexpected error occurred.';
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Extraction Failed',
                    message: msg,
                    variant: 'error',
                    mode:    'sticky'
                }));
                this.isLoading = false;
            });
    }
}
