using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.SampleFrames
{
    public class ExpressionItem
    {
        public FieldEnum Field { get; set; }
        public OperationEnum Operation { get; set; }
        public object Value { get; set; }
    }
}
