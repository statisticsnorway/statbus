using System.Linq;
using System.Threading.Tasks;
using nscreg.Business.SampleFrame;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Models.SampleFrame;
using Serialize.Linq.Serializers;

namespace nscreg.Services.SampleFrames
{
    /// <summary>
    /// Sample frame service
    /// </summary>
    public class SampleFrameService : ISampleFrameService
    {
        private readonly NSCRegDbContext _context;
        private readonly ExpressionParser _expressionParser;

        public SampleFrameService(NSCRegDbContext context)
        {
            _context = context;
            _expressionParser = new ExpressionParser();
        }

        /// <summary>
        /// Creates sample frame
        /// </summary>
        /// <param name="sfExpression"></param>
        /// <param name="sampleFrame"></param>
        /// <returns></returns>
        public async Task CreateAsync(SFExpression sfExpression, SampleFrame sampleFrame)
        {
            var predicate = _expressionParser.Parse(sfExpression);
            var serializer = new ExpressionSerializer(new JsonSerializer());
            serializer.AddKnownType(typeof(StatUnitStatuses));
         
            sampleFrame.Predicate = serializer.SerializeText(predicate);
            await _context.SampleFrames.AddAsync(sampleFrame);
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Edit sample frame
        /// </summary>
        /// <param name="sfExpression"></param>
        /// <param name="sampleFrame"></param>
        /// <returns></returns>
        public async Task EditAsync(SFExpression sfExpression, SampleFrame sampleFrame)
        {
            var predicate = _expressionParser.Parse(sfExpression);
            var serializer = new ExpressionSerializer(new JsonSerializer());
            serializer.AddKnownType(typeof(StatUnitStatuses));
            
            var existingSampleFrame = _context.SampleFrames.FirstOrDefault(sf => sf.Id == sampleFrame.Id);
            existingSampleFrame.Name = sampleFrame.Name;
            existingSampleFrame.Predicate = serializer.SerializeText(predicate);
            existingSampleFrame.Fields = sampleFrame.Fields;
            existingSampleFrame.UserId = sampleFrame.UserId;
            
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Delete sample frame
        /// </summary>
        /// <param name="id"></param>
        public async void Delete(int id)
        {
            var existingSampleFrame = _context.SampleFrames.FirstOrDefault(sf => sf.Id == id);
            _context.SampleFrames.Remove(existingSampleFrame);

            await _context.SaveChangesAsync();
        }
    }
}
