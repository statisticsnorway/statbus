using System;
using System.Threading.Tasks;
using nscreg.Business.SampleFrame;
using nscreg.Data;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Services.SampleFrames
{
    public class SampleFrameService : ISampleFrameService
    {
        private readonly NSCRegDbContext _context;
        private readonly ExpressionParser _expressionParser;

        public SampleFrameService(NSCRegDbContext context)
        {
            _context = context;
            _expressionParser = new ExpressionParser();
        }

        public async Task CreateAsync(Expression expression)
        {
            _expressionParser.Parse(expression);
        }

        public async Task EditAsync(Expression expression)
        {
            throw new NotImplementedException();
        }

        public async void DeleteAsync(int id)
        {
            throw new NotImplementedException();
        }
    }
}
