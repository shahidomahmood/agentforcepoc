import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getDashboardData from '@salesforce/apex/UnderwriterDashboardController.getDashboardData';

const RECENT_COLUMNS = [
    { label: 'Submission', fieldName: 'name',           type: 'text', wrapText: false, sortable: true },
    { label: 'Broker',     fieldName: 'brokerName',     type: 'text', wrapText: false },
    {
        label: 'Received', fieldName: 'receivedDate', type: 'date',
        typeAttributes: { month: '2-digit', day: '2-digit', year: 'numeric' }
    },
    { label: 'Status',   fieldName: 'status',         type: 'text', initialWidth: 180 },
    { label: 'Priority', fieldName: 'reviewPriority', type: 'text', initialWidth: 150 },
    {
        type: 'button', initialWidth: 90,
        typeAttributes: { label: 'View', name: 'view', variant: 'base' }
    }
];

const MISSING_COLUMNS = [
    { label: 'Submission',    fieldName: 'submissionName', type: 'text', wrapText: false, sortable: true },
    {
        label: 'Missing Items', fieldName: 'missingCount', type: 'number',
        initialWidth: 140, cellAttributes: { alignment: 'center' }
    },
    { label: 'Broker', fieldName: 'brokerName', type: 'text', wrapText: false },
    {
        label: 'Received', fieldName: 'receivedDate', type: 'date',
        typeAttributes: { month: '2-digit', day: '2-digit', year: 'numeric' }
    },
    {
        type: 'button', initialWidth: 90,
        typeAttributes: { label: 'View', name: 'view', variant: 'base' }
    }
];

export default class UnderwriterDashboard extends NavigationMixin(LightningElement) {
    isLoading      = true;
    hasError       = false;
    _wiredResult;
    _data;

    recentColumns  = RECENT_COLUMNS;
    missingColumns = MISSING_COLUMNS;

    @wire(getDashboardData)
    wiredDashboard(result) {
        this._wiredResult = result;
        if (result.data) {
            this._data     = result.data;
            this.isLoading = false;
            this.hasError  = false;
        } else if (result.error) {
            console.error('UnderwriterDashboard error:', JSON.stringify(result.error));
            this.isLoading = false;
            this.hasError  = true;
        }
    }

    // ── KPIs ─────────────────────────────────────────────────────────────

    get totalSubmissions()    { return this._data?.totalSubmissions    ?? 0; }
    get newSubmissions()      { return this._data?.newSubmissions       ?? 0; }
    get documentsReceived()   { return this._data?.documentsReceived    ?? 0; }
    get pendingReview()       { return this._data?.pendingReview        ?? 0; }
    get missingInformation()  { return this._data?.missingInformation   ?? 0; }
    get highRiskSubmissions() { return this._data?.highRiskSubmissions  ?? 0; }

    // ── Charts ───────────────────────────────────────────────────────────

    get intakeByDay()     { return this._data?.intakeByDay     ?? []; }
    get statusBreakdown() { return this._data?.statusBreakdown ?? []; }
    get documentsByType() { return this._data?.documentsByType ?? []; }

    get riskDistribution() {
        return this._data?.riskDistribution ?? [];
    }

    get hasIntakeData() { return this.intakeByDay.length > 0; }

    // ── Tables ───────────────────────────────────────────────────────────

    get missingInfoQueue() { return this._data?.missingInfoQueue ?? []; }
    get recentActivity()   { return this._data?.recentActivity   ?? []; }
    get hasMissingItems()  { return this.missingInfoQueue.length > 0; }
    get hasRecentItems()   { return this.recentActivity.length   > 0; }

    // ── Handlers ─────────────────────────────────────────────────────────

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this._wiredResult);
    }

    handleRowAction(event) {
        const { action, row } = event.detail;
        if (action.name === 'view') {
            const id = row.submissionId;
            if (id) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: { recordId: id, actionName: 'view' }
                });
            }
        }
    }
}
