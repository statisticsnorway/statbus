namespace nscreg.Business.SampleFrames
{
    public class ExpressionGroup
    {
        public ExpressionTuple<ExpressionGroup>[] Groups { get; set; }
        public ExpressionTuple<Rule>[] Rules { get; set; }
    }
}
