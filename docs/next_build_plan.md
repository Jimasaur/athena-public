# Athena build direction

The product direction is work intake and coordination. Voice is one entry point; the operator's work queue and reviewed handoff are the center of the product.

## Current slice

- Work items with ownership labels, status, priority, due dates, next steps, and resolution notes.
- Staff web intake and conversion from existing voice idea capture.
- Searchable queue views for open, needs review, unassigned, overdue, and all work.
- Linked source conversations and ideas, with work event history and stale-edit protection.
- Prepared, approved webhook handoffs with revision checks, idempotency keys, simulated delivery, and uncertain-delivery reconciliation.
- A synthetic demonstration that requires no live provider credentials.

## Next useful validation

Choose one operational intake workflow and the downstream system that already owns its work. Measure whether staff can capture enough context, assign ownership, make a reviewed handoff, and find the result without returning to scattered messages.

Record delivery acknowledgement separately from the business outcome. Measure requests with an owner, time to first reviewed handoff, failed/unknown handoffs, and work explicitly resolved with evidence. These are proposed pilot measures, not existing production results.

## Expansion order

1. Add team identity and permissions, replacing owner labels with actual assignments.
2. Add one connector with documented receiver deduplication and a way to reconcile delivery.
3. Extend voice capture to generic work templates and add one input channel selected by the pilot.
4. Add reminders and service targets after the ownership and queue workflow is proven.
5. Add downstream status synchronization and validated outcome reporting.

Keep the existing live voice path reliable while adding the work layer. Review approval boundaries, process interruption, stale revisions, and uncertain external results for every connector. Optional sidecars support the application; they do not define the product category.
