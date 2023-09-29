using nscreg.Data.Entities;
using System;
using System.Globalization;
using System.Reflection;
using nscreg.Data.Constants;
using static nscreg.Utilities.JsonPathHelper;
using NLog;

namespace nscreg.Business.DataSources
{
    public static class PropertyParser
    {
        private static readonly ILogger _logger = LogManager.GetCurrentClassLogger();

        public static object ConvertOrDefault(Type type, string raw)
        {
            try
            {
                if (type != typeof(DateTimeOffset)) return Convert.ChangeType(raw, type, CultureInfo.InvariantCulture);
                DateTimeOffset.TryParse(raw, out var date);
                return date;
            }
            catch (Exception ex)
            {
                _logger.Debug<Exception>("Error in ConvertOrDefault", ex);
                return type.GetTypeInfo().IsValueType ? Activator.CreateInstance(type) : null;
            }
        }

        public static Activity ParseActivity(string propPath, string value, Activity prev)
        {
            var result = prev ?? new Activity();
            switch (PathHead(propPath))
            {
                case nameof(Activity.ActivityType):
                    if (value == null)
                    {
                        result.ActivityType = ActivityTypes.Primary;
                        break;
                    }
                    if (Enum.TryParse(value, true, out ActivityTypes activityType))
                        result.ActivityType = activityType;
                    else throw BadValueFor<ActivityTypes>(propPath, value);
                    break;
                case nameof(Activity.ActivityCategory):
                    result.ActivityCategory = ParseActivityCategory(PathTail(propPath), value, result.ActivityCategory);
                    break;
                case nameof(ActivityCategory.Code):
                case nameof(ActivityCategory.Name):
                    result.ActivityCategory = ParseActivityCategory(propPath, value, result.ActivityCategory);
                    break;
                case nameof(Activity.ActivityYear):
                    if (value == null)
                    {
                        result.ActivityYear = DateTime.Now.Year-1;
                        break;
                    }
                    if (int.TryParse(value, out var activityYear))
                        result.ActivityYear = activityYear;
                    else throw BadValueFor<int>(propPath, value);
                    break;
                case nameof(Activity.Employees):
                    if (value == null)
                    {
                        result.Employees = null;
                        break;
                    }
                    if (int.TryParse(value, out var employees))
                        result.Employees = employees;
                    else throw BadValueFor<int>(propPath, value);
                    break;
                case nameof(Activity.Turnover):
                    result.Turnover = decimal.TryParse(value, out var turnover) ? (decimal?) turnover : null;
                    break;
                default: throw UnsupportedPropertyOf<Activity>(propPath);
            }
            return result;
        }

        public static Person ParsePerson(string propPath, string value, Person prev, string newRole = null)
        {
            var result = prev ?? new Person();
            switch (PathHead(propPath))
            {
                case nameof(Person.Role):
                    if(int.TryParse(value, out var val))
                        result.Role = val;
                    else throw BadValueFor<Person>(propPath, newRole);
                    break;
                case nameof(Person.GivenName):
                    result.GivenName = value;
                    break;
                case nameof(Person.MiddleName):
                    result.MiddleName = value;
                    break;
                case nameof(Person.Surname):
                    result.Surname = value;
                    break;
                case nameof(Person.PersonalId):
                    result.PersonalId = value;
                    break;
                case nameof(Person.BirthDate):
                    if (value == null) {result.BirthDate = null; break; }
                    if (DateTime.TryParse(value, out var birthDate)) result.BirthDate = birthDate;
                    else throw BadValueFor<Person>(propPath, value);
                    break;

                case nameof(Person.NationalityCode):
                    if (result.NationalityCode == null)
                    {
                        result.NationalityCode = ParseCountry(propPath.Split('.',2)[1], value, result.NationalityCode);
                    }
                    break;
                case nameof(Person.Sex):
                    result.Sex = ParsePersonSex(value);
                    break;
                case nameof(Person.PhoneNumber):
                    result.PhoneNumber = value;
                    break;
                case nameof(Person.PhoneNumber1):
                    result.PhoneNumber1 = value;
                    break;
                //case nameof(Person.Code)
                default: throw UnsupportedPropertyOf<Person>(propPath);
            }
            return result;
        }

        public static Address ParseAddress(string propPath, string value, Address prev)
        {
            var result = prev ?? new Address();
            switch (PathHead(propPath))
            {
                case nameof(Address.AddressPart1):
                    result.AddressPart1 = value;
                    break;
                case nameof(Address.AddressPart2):
                    result.AddressPart2 = value;
                    break;
                case nameof(Address.AddressPart3):
                    result.AddressPart3 = value;
                    break;
                case nameof(Address.Region):
                    result.Region = ParseRegion(PathTail(propPath), value, result.Region);
                    break;
                default: throw UnsupportedPropertyOf<Address>(propPath);
            }
            return result;
        }

        public static ActivityCategory ParseActivityCategory(string prop, string value, ActivityCategory prev)
        {
            var result = prev ?? new ActivityCategory();
            switch (prop)
            {
                case nameof(ActivityCategory.Code):
                    result.Code = value;
                    break;
                case nameof(ActivityCategory.Name):
                    result.Name = value;
                    break;
                case nameof(ActivityCategory.Section):
                    result.Section = value;
                    break;
                default: throw UnsupportedPropertyOf<ActivityCategory>(prop);
            }
            return result;
        }

        public static Region ParseRegion(string prop, string value, Region prev)
        {
            var result = prev ?? new Region();
            switch (prop)
            {
                case nameof(Region.Code):
                    result.Code = value;
                    break;
                case nameof(Region.Name):
                    result.Name = value;
                    break;
                case nameof(Region.AdminstrativeCenter):
                    result.AdminstrativeCenter = value;
                    break;
                default: throw UnsupportedPropertyOf<Region>(prop);
            }
            return result;
        }

        public static Country ParseCountry(string prop, string value, Country prev)
        {
            var result = prev ?? new Country();
            switch (prop)
            {
                case nameof(Country.Id):
                    result.Id = int.Parse(value);
                    break;
                case nameof(Country.Code):
                    result.Code = value;
                    break;
                case nameof(Country.Name):
                    result.Name = value;
                    break;
                default: throw UnsupportedPropertyOf<Country>(prop);
            }
            return result;
        }

        public static ForeignParticipation ParseForeignParticipation(string prop, string value, ForeignParticipation prev)
        {
            var result = prev ?? new ForeignParticipation();
            switch (prop)
            {
                case nameof(ForeignParticipation.Name):
                    result.Name = value;
                    break;
                case nameof(ForeignParticipation.Code):
                    result.Code = value;
                    break;
                default: throw UnsupportedPropertyOf<ForeignParticipation>(prop);
            }
            return result;
        }

        public static LegalForm ParseLegalForm(string prop, string value, LegalForm prev)
        {
            var result = prev ?? new LegalForm();
            switch (prop)
            {
                case nameof(LegalForm.Code):
                    result.Code = value;
                    break;
                case nameof(LegalForm.Name):
                    result.Name = value;
                    break;
                default: throw UnsupportedPropertyOf<LegalForm>(prop);
            }
            return result;
        }

        public static SectorCode ParseSectorCode(string prop, string value, SectorCode prev)
        {
            var result = prev ?? new SectorCode();
            switch (prop)
            {
                case nameof(SectorCode.Code):
                    result.Code = value;
                    break;
                case nameof(SectorCode.Name):
                    result.Name = value;
                    break;
                default: throw UnsupportedPropertyOf<SectorCode>(prop);
            }
            return result;
        }

        public static DataSourceClassification ParseDataSourceClassification(string prop, string value,
            DataSourceClassification prev)
        {
            var result = prev ?? new DataSourceClassification();
            switch (prop)
            {
                case nameof(DataSourceClassification.Name):
                    result.Name = value;
                    break;
                case nameof(DataSourceClassification.Code):
                    result.Code = value;
                    break;
                default: throw UnsupportedPropertyOf<DataSourceClassification>(prop);
            }
            return result;
        }

        public static UnitSize ParseSize(string prop, string value, UnitSize prev)
        {
            var result = prev ?? new UnitSize();
            switch (prop)
            {
                case nameof(UnitSize.Name):
                    result.Name = value;
                    break;
                default: throw UnsupportedPropertyOf<UnitSize>(prop);
            }

            return result;
        }

        public static UnitStatus ParseUnitStatus(string prop, string value, UnitStatus prev)
        {
            var result = prev ?? new UnitStatus();
            switch (prop)
            {
                case nameof(UnitStatus.Name):
                    result.Name = value;
                    break;
                case nameof(UnitStatus.Code):
                    result.Code = value;
                    break;
                default: throw UnsupportedPropertyOf<UnitStatus>(prop);
            }

            return result;
        }

        public static ReorgType ParseReorgType(string prop, string value, ReorgType prev)
        {
            var result = prev ?? new ReorgType();
            switch (prop)
            {
                case nameof(UnitStatus.Name):
                    result.Name = value;
                    break;
                case nameof(UnitStatus.Code):
                    result.Code = value;
                    break;
                default: throw UnsupportedPropertyOf<ReorgType>(prop);
            }

            return result;
        }

        public static RegistrationReason ParseRegistrationReason(string prop, string value, RegistrationReason prev)
        {
            var result = prev ?? new RegistrationReason();
            switch (prop)
            {
                case nameof(UnitStatus.Name):
                    result.Name = value;
                    break;
                case nameof(UnitStatus.Code):
                    result.Code = value;
                    break;
                default: throw UnsupportedPropertyOf<RegistrationReason>(prop);
            }

            return result;
        }

        public static byte ParsePersonSex(string value)
        {
            var result = value == "1" ? (byte)1 : (byte)2;
            return result;
        }

        public static bool SetPersonStatUnitOwnProperties(string path, PersonStatisticalUnit entity, string value)
        {
            switch (path)
            {
                case "Role":
                    entity.PersonTypeId = Convert.ToInt32(value);
                    if (entity.Person != null)
                    {
                        entity.Person.Role = Convert.ToInt32(value);
                    }
                    break;
                default:
                    return false;
            }
            return true;
        }

        private static Exception UnsupportedPropertyOf<T>(string propPath) =>
            new Exception($"Property path `{propPath}` in type `{typeof(T).Name}` is not supported");

        private static Exception BadValueFor<T>(string propPath, string rawValue) =>
            new Exception($"Value `{rawValue}` at property path `{propPath}` in type `{typeof(T).Name}` couldn't be parsed");
    }
}
