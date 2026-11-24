/**
 * How a statistical variable reported on a legal unit and on its establishments adds up: the legal
 * unit's total is the larger of its own value and its establishments' sum (public.jsonb_stats_covers),
 * because the establishments are parts of it. Shown where statistical variables are defined
 * (Admin, Statistical Variables) and where they are imported (legal units, establishments), so the
 * counting a user sees in Reports is explained where the numbers go in. The full text, with the UN
 * and Eurostat references, is doc/METHODOLOGICAL_GUIDELINE.md section 3.2.3.
 */
export const STATISTICAL_VARIABLE_COUNTING_DOC_URL =
  "https://github.com/statisticsnorway/statbus/blob/master/doc/METHODOLOGICAL_GUIDELINE.md#323-how-statistical-variables-add-up-between-legal-units-and-establishments";

export function StatisticalVariableCounting() {
  return (
    <div className="space-y-2 text-sm">
      <p>
        A legal unit&apos;s establishments are parts of it, so a value such as
        the number of employees may be reported on the legal unit, on its
        establishments, or on both, and on both it describes the same people.
        StatBus counts it once: a legal unit&apos;s total is the larger of its
        own value and its establishments&apos; sum. An enterprise adds its legal
        units.
      </p>
      <p>
        This follows the UN Guidelines on Statistical Business Registers and the
        Eurostat Business Registers Recommendations Manual. Where the two levels
        disagree, the Data quality checks Establishments Above Legal Unit and
        Legal Unit Above Establishments list the units to review.
      </p>
      <p>
        <a
          href={STATISTICAL_VARIABLE_COUNTING_DOC_URL}
          target="_blank"
          rel="noreferrer"
          className="underline"
        >
          How statistical variables add up (methodological guideline)
        </a>
      </p>
    </div>
  );
}
