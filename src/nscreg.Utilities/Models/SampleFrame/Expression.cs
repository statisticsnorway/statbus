using System;
using System.Collections.Generic;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Utilities.Models.SampleFrame
{
    public class SfExpression
    {
        public List<Tuple<ExpressionItem, ComparisonEnum?>> ExpressionItems { get; set; }
        public SfExpression FirstSfExpression { get; set; }
        public SfExpression SecondSfExpression { get; set; }
        public ComparisonEnum Comparison { get; set; }
    }
}
