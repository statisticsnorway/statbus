using System;
using System.Collections.Generic;
using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.DataSources
{
    /// <summary>
    /// Dispatch model
    /// </summary>
    public class SubmitM
    {
        public string Name { get; set; }
        public string Description { get; set; }
        public int AllowedOperations { get; set; }
        public IEnumerable<string> AttributesToCheck { get; set; }
        public IEnumerable<string> OriginalCsvAttributes { get; set; }
        public string Priority { get; set; }
        public int StatUnitType { get; set; }
        public string Restrictions { get; set; }
        public string VariablesMapping { get; set; }
        public string CsvDelimiter { get; set; }
        public int CsvSkipCount { get; set; }
        public int DataSourceUploadType { get; set; }

        /// <summary>
        /// Entity Creation Method
        /// </summary>
        /// <returns></returns>
        public DataSource CreateEntity(string userId)
        {
            if (!Enum.TryParse(Priority, out DataSourcePriority priority))
            {
                priority = DataSourcePriority.NotTrusted;
            }
            return new DataSource
            {
                Name = Name,
                Description = Description,
                Priority = priority,
                AllowedOperations = (DataSourceAllowedOperation) AllowedOperations,
                StatUnitType = (StatUnitTypes) StatUnitType,
                Restrictions = Restrictions,
                VariablesMapping = VariablesMapping,
                AttributesToCheckArray = AttributesToCheck,
                OriginalAttributesArray = OriginalCsvAttributes,
                CsvDelimiter = CsvDelimiter,
                CsvSkipCount = CsvSkipCount,
                DataSourceUploadType = (DataSourceUploadTypes)DataSourceUploadType,
                UserId = userId
            };
        }

        /// <summary>
        /// Entity Update Method
        /// </summary>
        /// <returns></returns>
        public void UpdateEntity(DataSource entity, string userId)
        {
            entity.Name = Name;
            entity.Description = Description;
            if (Enum.TryParse(Priority, out DataSourcePriority priority))
            {
                entity.Priority = priority;
            }
            entity.AllowedOperations = (DataSourceAllowedOperation) AllowedOperations;
            entity.StatUnitType = (StatUnitTypes) StatUnitType;
            entity.Restrictions = Restrictions;
            entity.VariablesMapping = VariablesMapping;
            entity.AttributesToCheckArray = AttributesToCheck;
            entity.OriginalAttributesArray = OriginalCsvAttributes;
            entity.CsvDelimiter = CsvDelimiter;
            entity.CsvSkipCount = CsvSkipCount;
            entity.DataSourceUploadType = (DataSourceUploadTypes) DataSourceUploadType;
            entity.UserId = userId;
        }
    }

    /// <summary>
    /// Data Source Submission Validation Model
    /// </summary>
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once ArrangeTypeModifiers
    class DataSourceSubmitMValidator : AbstractValidator<SubmitM>
    {
        public DataSourceSubmitMValidator()
        {
            RuleFor(x => x.Name)
                .NotEmpty()
                .WithMessage(nameof(Resource.DataSourceNameIsRequired));

            RuleFor(x => x.AttributesToCheck)
                .NotEmpty()
                .WithMessage(nameof(Resource.DataSourceAttributesToCheckIsRequired));

            RuleFor(x => x.CsvDelimiter)
                .NotEmpty()
                .WithMessage(nameof(Resource.DataSourceCsvDelimiterNotValid));

            RuleFor(x => x.CsvSkipCount)
                .GreaterThanOrEqualTo(0)
                .WithMessage(nameof(Resource.DataSourceCsvSkipCountNotValid));
        }
    }
}
