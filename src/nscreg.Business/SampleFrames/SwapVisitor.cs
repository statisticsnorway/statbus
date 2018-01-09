using System.Linq.Expressions;

namespace nscreg.Business.SampleFrames
{
    /// <inheritdoc />
    /// <summary>
    /// Visitor to combine two lambda expressions
    /// </summary>
    public class SwapVisitor : ExpressionVisitor
    {
        private readonly Expression _from, _to;

        public SwapVisitor(Expression from, Expression to)
        {
            _from = from;
            _to = to;
        }

        public override Expression Visit(Expression node)
        {
            return node == _from ? _to : base.Visit(node);
        }
    }
}
