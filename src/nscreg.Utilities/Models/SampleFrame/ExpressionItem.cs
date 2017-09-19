using nscreg.Utilities.Enums.SampleFrame;

namespace nscreg.Utilities.Models.SampleFrame
{
    public class ExpressionItem
    {
        public FieldEnum Field { get; set; }
        public OperationEnum Operation { get; set; }
        public object Value { get; set; }
    }
}