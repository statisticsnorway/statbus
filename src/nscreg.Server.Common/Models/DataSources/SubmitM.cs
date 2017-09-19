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
    public class SubmitM
    {
        public string Name { get; set; }
        public string Description { get; set; }
        public int AllowedOperations { get; set; }
        public IEnumerable<string> AttributesToCheck { get; set; }
        public string Priority { get; set; }
        public int StatUnitType { get; set; }
        public string Restrictions { get; set; }
        public string VariablesMapping { get; set; }

        public DataSource CreateEntity()
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
            };
        }

        public void UpdateEntity(DataSource entity)
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
        }
    }

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
        }
    }
}
