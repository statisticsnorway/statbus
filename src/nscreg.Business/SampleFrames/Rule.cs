using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.SampleFrames
{
    public class Rule
    {
        public FieldEnum Field { get; set; }
        public OperationEnum Operation { get; set; }
        public object Value { get; set; }
    }
}
