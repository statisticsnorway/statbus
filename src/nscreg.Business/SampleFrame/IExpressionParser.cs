using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Business.SampleFrame
{
    public interface IExpressionParser
    {
        string Parse(Expression expression);
    }
}
