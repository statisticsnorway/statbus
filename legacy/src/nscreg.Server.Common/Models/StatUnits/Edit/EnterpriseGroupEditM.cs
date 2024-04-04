using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using FluentValidation;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Resources.Languages;
using nscreg.Utilities.Enums;
using Newtonsoft.Json;

namespace nscreg.Server.Common.Models.StatUnits.Edit
{
    public class EnterpriseGroupEditM : IStatUnitM
    {
        [Required]
        public int? RegId { get; set; }

        public string StatId { get; set; }

        [DataType(DataType.Date)]
        public DateTime? StatIdDate { get; set; }

        public int? TaxRegId { get; set; }

        [DataType(DataType.Date)]
        public DateTime? TaxRegDate { get; set; }

        public int? ExternalId { get; set; }
        public string ExternalIdType { get; set; }

        [DataType(DataType.Date)]
        public DateTime? ExternalIdDate { get; set; }

        public string DataSource { get; set; }

        public string Name { get; set; }

        public string ShortName { get; set; }
        public AddressM Address { get; set; }

        [DataType(DataType.PhoneNumber)]
        public string TelephoneNo { get; set; }

        [DataType(DataType.EmailAddress)]
        public string EmailAddress { get; set; }

        [DataType(DataType.Url)]
        public string WebAddress { get; set; }

        public string EntGroupType { get; set; }

        [DataType(DataType.Date)]
        public DateTime RegistrationDate { get; set; }

        public int? RegistrationReasonId { get; set; }

        [DataType(DataType.Date)]
        public DateTime? LiqDateStart { get; set; }

        [DataType(DataType.Date)]
        public DateTime? LiqDateEnd { get; set; }

        public string LiqReason { get; set; }
        public string SuspensionStart { get; set; }
        public string SuspensionEnd { get; set; }
        public string ReorgTypeCode { get; set; }

        [DataType(DataType.Date)]
        public DateTime? ReorgDate { get; set; }

        public string ReorgReferences { get; set; }
        public AddressM ActualAddress { get; set; }
        public AddressM PostalAddress { get; set; }
        public string ContactPerson { get; set; }
        public int? Employees { get; set; }
        public int? NumOfPeopleEmp { get; set; }

        public int? EmployeesYear { get; set; }

        [DataType(DataType.Date)]
        public DateTime? EmployeesDate { get; set; }

        public decimal? Turnover { get; set; }

        public int? TurnoverYear { get; set; }

        [DataType(DataType.Date)]
        public DateTime? TurnoverDate { get; set; }

        public string Status { get; set; }

        [DataType(DataType.Date)]
        public DateTime StatusDate { get; set; }

        public string Notes { get; set; }
        public int[] EnterpriseUnits { get; set; }
        public ChangeReasons ChangeReason { get; set; }
        public string EditComment { get; set; }
        public int? SizeId { get; set; }
        public int? DataSourceClassificationId { get; set; }
        public int? ReorgTypeId { get; set; }
        public int? UnitStatusId { get; set; }

        public IEnumerable<Permission> Permissions { get; set; }

        [JsonIgnore]
        public DataAccessPermissions DataAccess
        {
            get => Permissions != null ? new DataAccessPermissions(Permissions) : null;
            set => Permissions = value.Permissions;
        }
    }

    public class EnterpriseGroupEditMValidator : AbstractValidator<EnterpriseGroupEditM>
    {
        public EnterpriseGroupEditMValidator()
        {
            RuleFor(v => v.ChangeReason)
                .NotEmpty()
                .Must(v =>
                    v == ChangeReasons.Edit ||
                    v == ChangeReasons.Correction)
                .WithMessage(nameof(Resource.ChangeReasonMandatory));
            RuleFor(v => v.EditComment)
                .NotEmpty()
                .When(v => v.ChangeReason == ChangeReasons.Edit)
                .WithMessage(nameof(Resource.EditCommentMandatory));
            RuleFor(x => x.EmailAddress)
                .EmailAddress();
        }
    }
}
