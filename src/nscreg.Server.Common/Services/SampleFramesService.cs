using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.SampleFrames;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Utilities;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums.Predicate;
using Newtonsoft.Json;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Sample frame service
    /// </summary>
    public class SampleFramesService
    {
        private readonly NSCRegDbContext _context;
        private readonly ExpressionTreeParser<StatisticalUnit> _statUnitExprParser;
        private readonly ExpressionTreeParser<EnterpriseGroup> _enterpriseGroupExprParser;

        public SampleFramesService(NSCRegDbContext context)
        {
            _context = context;
            _statUnitExprParser = new ExpressionTreeParser<StatisticalUnit>();
            _enterpriseGroupExprParser = new ExpressionTreeParser<EnterpriseGroup>();
        }

        /// <summary>
        /// Gets a list of sample frames
        /// </summary>
        /// <param name="model">pagination settings</param>
        /// <returns></returns>
        public async Task<SearchVm<SampleFrameM>> GetAll(PaginatedQueryM model)
        {
            var query = _context.SampleFrames;
            var total = await query.CountAsync();
            return SearchVm<SampleFrameM>.Create(
                (await query
                    .Skip(Pagination.CalculateSkip(model.PageSize, model.Page, total))
                    .Take(model.PageSize)
                    .AsNoTracking()
                    .ToListAsync())
                .Select(SampleFrameM.Create),
                total);
        }

        /// <summary>
        /// Gets statistical units of sample frame
        /// </summary>
        /// <param name="id"></param>
        /// <returns></returns>
        public async Task<SampleFrameM> GetById(int id)
        {
            var entity = await _context.SampleFrames.FindAsync(id);
            if (entity == null) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            return SampleFrameM.Create(entity);
        }

        public async Task<IEnumerable<IReadOnlyDictionary<FieldEnum, string>>> Preview(int id, int? count = null)
        {
            var sampleFrame = await _context.SampleFrames.FindAsync(id);
            if (sampleFrame == null) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            var fields = JsonConvert.DeserializeObject<IEnumerable<FieldEnum>>(sampleFrame.Fields)
                .ToDictionary(key => key, key => Enum.GetName(typeof(FieldEnum), key));
            var predicateTree = JsonConvert.DeserializeObject<ExpressionGroup>(sampleFrame.Predicate);

            var units = await ExecuteSampleFrameOnStatUnits(count, predicateTree);
            var groups = await ExecuteSampleFrameOnEnterpriseGroupsAsync(count - units.Count, predicateTree);

            return units.Concat(groups).Select(unit =>
                fields.ToDictionary(field => field.Key, field => GetPropValue(unit, field.Value)));
        }

        private async Task<List<IStatisticalUnit>> ExecuteSampleFrameOnEnterpriseGroupsAsync(int? count, ExpressionGroup expressionGroup)
        {
            var predicate = _enterpriseGroupExprParser.Parse(expressionGroup);
            var query = _context.EnterpriseGroups
                .Where(predicate);
            if (count.HasValue)
                query = query.Take(count.Value);
            var groups = await query
                .AsNoTracking()
                .Cast<IStatisticalUnit>()
                .ToListAsync();
            return groups;
        }

        private async Task<List<IStatisticalUnit>> ExecuteSampleFrameOnStatUnits(int? count, ExpressionGroup expressionGroup)
        {
            var predicate = _statUnitExprParser.Parse(expressionGroup);
            var query = _context.StatisticalUnits
                .Where(predicate);
            if (count.HasValue)
                query = query.Take(count.Value);
            var units = await query
                .AsNoTracking()
                .Cast<IStatisticalUnit>()
                .ToListAsync();
            return units;
        }

        /// <summary>
        /// Creates sample frame
        /// </summary>
        /// <param name="model"></param>
        /// <param name="userId"></param>
        /// <returns></returns>
        public async Task<SampleFrameM> Create(SampleFrameM model, string userId)
        {
            var entity = model.CreateSampleFrame(userId);
            _context.SampleFrames.Add(entity);
            await _context.SaveChangesAsync();
            model.Id = entity.Id;
            return model;
        }

        /// <summary>
        /// Edits sample frame
        /// </summary>
        /// <param name="id"></param>
        /// <param name="model"></param>
        /// <param name="userId"></param>
        /// <returns></returns>
        public async Task Edit(int id, SampleFrameM model, string userId)
        {
            var existing = await _context.SampleFrames.FindAsync(id);
            if (existing == null) throw new NotFoundException(Resource.SampleFrameNotFound);
            model.UpdateSampleFrame(existing, userId);
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Deletes sample frame
        /// </summary>
        /// <param name="id"></param>
        public async Task Delete(int id)
        {
            var existing = await _context.SampleFrames.FindAsync(id);
            if (existing == null) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            _context.SampleFrames.Remove(existing);
            await _context.SaveChangesAsync();
        }

        private static string GetPropValue(IStatisticalUnit unit, string fieldName) =>
            unit.GetType().GetProperty(fieldName)?.GetValue(unit, null)?.ToString() ?? string.Empty;
    }
}
