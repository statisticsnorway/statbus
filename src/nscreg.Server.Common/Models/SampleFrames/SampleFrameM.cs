using System.Collections.Generic;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Server.Common.Models.SampleFrames
{
    public class SampleFrameM
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public SfExpression ExpressionTree { get; set; }
        public List<string> Fields { get; set; }
        public string UserId { get; set; }
    }
}
