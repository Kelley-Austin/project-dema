import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getScoreData from '@salesforce/apex/OpportunityScoreCalculator.getScoreData';
import recalculateScore from '@salesforce/apex/OpportunityScoreCalculator.recalculateScore';

const CIRCUMFERENCE = 2 * Math.PI * 54; // radius 54 in 120x120 viewBox

export default class OpportunityScorecard extends LightningElement {
    @api recordId;
    @track isLoading = false;

    _wiredResult;
    _scoreData;

    @wire(getScoreData, { opportunityId: '$recordId' })
    wiredScore(result) {
        this._wiredResult = result;
        if (result.data) {
            this._scoreData = result.data;
        } else if (result.error) {
            this._scoreData = undefined;
        }
    }

    get hasScore() {
        return this._scoreData != null && this._scoreData.compositeScore > 0;
    }

    get compositeScoreDisplay() {
        return Math.round(this._scoreData?.compositeScore ?? 0);
    }

    get dealSizeScoreDisplay() {
        return Math.round(this._scoreData?.dealSizeScore ?? 0);
    }

    get engagementScoreDisplay() {
        return Math.round(this._scoreData?.engagementScore ?? 0);
    }

    get competitiveRiskDisplay() {
        return Math.round(this._scoreData?.competitiveRisk ?? 0);
    }

    get circumference() {
        return CIRCUMFERENCE;
    }

    get dashOffset() {
        return CIRCUMFERENCE * (1 - this.compositeScoreDisplay / 100);
    }

    get ringColor() {
        const s = this.compositeScoreDisplay;
        if (s >= 75) return '#2e844a';
        if (s >= 50) return '#dd7a01';
        return '#ea001e';
    }

    get scoreRating() {
        const s = this.compositeScoreDisplay;
        if (s >= 75) return 'Strong Opportunity';
        if (s >= 50) return 'Moderate Opportunity';
        if (s >= 25) return 'Developing Opportunity';
        return 'Needs Attention';
    }

    get dealSizeBarStyle() {
        return `width: ${this.dealSizeScoreDisplay}%`;
    }

    get engagementBarStyle() {
        return `width: ${this.engagementScoreDisplay}%`;
    }

    get competitiveRiskBarStyle() {
        return `width: ${this.competitiveRiskDisplay}%`;
    }

    handleCalculate() {
        this.isLoading = true;
        recalculateScore({ opportunityId: this.recordId })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Score Updated',
                    message: 'Intelligence score has been calculated.',
                    variant: 'success'
                }));
                return refreshApex(this._wiredResult);
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message ?? 'Failed to calculate score.',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}
