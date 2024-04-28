using nscreg.Utilities.Attributes;

namespace nscreg.Utilities.Enums.Predicate
{
    /// <summary>
    ///     Predicate building fields
    /// </summary>
    public enum FieldEnum
    {
        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        UnitType = 1,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        Region = 2,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        MainActivity = 3,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        UnitStatusId = 4,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.GreaterThan, OperationEnum.GreaterThanOrEqual,
            OperationEnum.LessThan, OperationEnum.LessThanOrEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.InRange, OperationEnum.NotInRange)]
        Turnover = 5,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.GreaterThan, OperationEnum.GreaterThanOrEqual,
            OperationEnum.LessThan, OperationEnum.LessThanOrEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.InRange, OperationEnum.NotInRange)]
        TurnoverYear = 6,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.GreaterThan, OperationEnum.GreaterThanOrEqual,
            OperationEnum.LessThan, OperationEnum.LessThanOrEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.InRange, OperationEnum.NotInRange)]
        Employees = 7,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.GreaterThan, OperationEnum.GreaterThanOrEqual,
            OperationEnum.LessThan, OperationEnum.LessThanOrEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.InRange, OperationEnum.NotInRange)]
        EmployeesYear = 8,

        [OperationAllowed(OperationEnum.Equal, OperationEnum.NotEqual)]
        FreeEconZone = 9,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        ForeignParticipationId = 10,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        ParentId = 11,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        RegId = 12,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.Contains, OperationEnum.DoesNotContain)]
        Name = 13,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.Contains, OperationEnum.DoesNotContain)]
        StatId = 14,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.Contains, OperationEnum.DoesNotContain)]
        TaxRegId = 15,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.Contains, OperationEnum.DoesNotContain)]
        ExternalId = 16,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.Contains, OperationEnum.DoesNotContain)]
        ShortName = 17,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.Contains, OperationEnum.DoesNotContain)]
        TelephoneNo = 18,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        Address = 19,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.Contains, OperationEnum.DoesNotContain)]
        EmailAddress = 20,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList,
            OperationEnum.Contains, OperationEnum.DoesNotContain)]
        ContactPerson = 21,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        LegalFormId = 22,

        [OperationAllowed(
            OperationEnum.Equal, OperationEnum.NotEqual,
            OperationEnum.InList, OperationEnum.NotInList)]
        InstSectorCodeId = 23,

        ActualAddress = 24,
        ActivityCodes = 25,
        Size = 26,
        Notes = 27,
        PostalAddress = 28,
        ForeignParticipationCountry = 30
    }
}
