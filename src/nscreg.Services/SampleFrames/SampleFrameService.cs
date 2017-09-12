using System;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Business.SampleFrame;
using nscreg.Data;
using nscreg.Data.Entities;
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

        public async Task CreateAsync(SFExpression sfExpression, SampleFrame sampleFrame)
        {
            var predicate = _expressionParser.Parse(sfExpression);
            //var b = predicate.Compile();
            //var a = _context.StatisticalUnits.AsQueryable().Where("Id  2").ToList();
            sampleFrame.Predicate = predicate.ToString();
            await _context.SampleFrames.AddAsync(sampleFrame);
            await _context.SaveChangesAsync();
        }

        public async Task EditAsync(SFExpression sfExpression)
        {
            throw new NotImplementedException();
        }

        public async void DeleteAsync(int id)
        {
            throw new NotImplementedException();
        }
    }
}
