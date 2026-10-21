# Finmi interface update

The application defaults to Pure white and keeps the selectable palettes in
Settings. Shared typography uses the bundled Be Vietnam Pro font and respects
system text scaling.

This update includes the two-tab income/expense form with amount, category,
content and date; month/year statistics with selectable days and months;
period-aware flow and pie charts; colored category icons and expandable budget
overages; the assistant bottom sheet; and updated navigation and scanner labels.
Recurring entries are added from the header plus button. Home and authentication
use the approved branding stored in `assets/branding/finmi/`.

## Database deployment

Local database schema v14 adds an income note without removing existing data.
Before releasing synchronization of that field, apply
`supabase/migrations/20261020100000_income_note.sql` to the deployed backend.
The migration updates both upload and download RPCs. It has not been deployed
to a remote database as part of this interface work.

## Validation

The full Flutter test suite passed 312 tests, followed by 21 final interface
checks, and Flutter analysis reported no issues. Visual tests render at
320/390/430 logical pixels and text scales 1/1.3/2. Their generated screenshots
and logs go to the ignored `artifacts/` directory.

Device camera permissions, live OCR, remote authentication, bank launch and
payment confirmation still require device/service validation.
