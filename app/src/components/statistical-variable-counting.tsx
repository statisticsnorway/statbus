/**
 * How a statistical variable reported on a legal unit and on its establishments adds up. Each summed
 * variable chooses (stat_definition.lu_es_rollup, s465ff): add the legal unit's own value to its
 * establishments' sum (the default, for values reported on one level), or take the larger of the two
 * (for values both levels report about the same people, so they count once:
 * public.jsonb_stats_covers). Shown where statistical variables are defined (Admin, Statistical
 * Variables) and where they are imported (legal units, establishments), so the counting a user sees in
 * Reports is explained where the numbers go in. The full text, with the UN and Eurostat references,
 * is doc/METHODOLOGICAL_GUIDELINE.md section 3.2.3.
 */
export const STATISTICAL_VARIABLE_COUNTING_DOC_URL =
  "https://github.com/statisticsnorway/statbus/blob/master/doc/METHODOLOGICAL_GUIDELINE.md#323-how-statistical-variables-add-up-between-legal-units-and-establishments";

export function StatisticalVariableCounting() {
  return (
    <div className="space-y-2 text-sm">
      <p>
        A legal unit&apos;s establishments are parts of it, so a value such as
        the number of employees may be reported on the legal unit, on its
        establishments, or on both. Each variable chooses how a legal
        unit&apos;s total is made (Legal unit total above):
      </p>
      <ul className="list-disc pl-5">
        <li>
          <strong>Add</strong>: its own value plus its establishments&apos;
          sum, for a value reported on one level only. In the Links tree:
          Σ 369 = 364 + 5.
        </li>
        <li>
          <strong>Larger of</strong>: its own value or its establishments&apos;
          sum, whichever is larger, for a value both levels report about the
          same people, so they count once. In the Links tree: Σ 364 = max(364, 5).
        </li>
      </ul>
      <p>An enterprise adds its legal units.</p>
      <p>
        This follows the UN Guidelines on Statistical Business Registers and the
        Eurostat Business Registers Recommendations Manual. For a variable set
        to Larger of, where the two levels disagree, the Data quality checks
        Establishments Above Legal Unit and Legal Unit Above Establishments list
        the units to review.
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
