using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using nscreg.Business.SampleFrame;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Utilities.Models.SampleFrame;
using Newtonsoft.Json;

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
            sampleFrame.Predicate = JsonConvert.SerializeObject(sfExpression);
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
            var existingSampleFrame = _context.SampleFrames.FirstOrDefault(sf => sf.Id == sampleFrame.Id);
            existingSampleFrame.Name = sampleFrame.Name;
            existingSampleFrame.Predicate = JsonConvert.SerializeObject(sfExpression);
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

        /// <summary>
        /// Get list of statistical unit
        /// </summary>
        /// <param name="id">Sample frame id</param>
        /// <returns></returns>
        public Dictionary<string, string[]> View(int id)
        {
            var sampleFrame = _context.SampleFrames.FirstOrDefault(x => x.Id == id);
            if (sampleFrame == null) return null;

            var sfExpression = JsonConvert.DeserializeObject<SFExpression>(sampleFrame.Predicate);
            var predicate = _expressionParser.Parse(sfExpression);

            var statUnits = _context.StatisticalUnits.Where(predicate).ToList();

            var result = new Dictionary<string, string[]>();
            var fields = sampleFrame.Fields.Split(';');
            foreach (var unit in statUnits)
            {
                foreach (var field in fields)
                {
                    if (result.Any(x => x.Key == field))
                    {
                        var existed = result[field];
                        result[field] = existed.Concat(GetPropValue(unit, field)).ToArray();
                    }
                    else
                    {
                        result.Add(field, GetPropValue(unit, field));
                    }
                }
            }
            return result;
        }

        private static string[] GetPropValue(StatisticalUnit src, string propName)
        {
            return new[] { src.GetType().GetProperty(propName).GetValue(src, null).ToString() };
        }

    }
}
