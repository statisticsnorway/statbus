using System;
using System.Linq;
using AutoMapper;
using nscreg.Data.Entities;
using nscreg.Server.Models.Addresses;
using nscreg.Server.Models.Lookup;
using nscreg.Server.Models.Soates;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Models
{
    public static class AutoMapperConfiguration
    {
        public static void Configure()
        {
            Mapper.Initialize(x => { x.AddProfile<AutoMapperProfile>(); });
        }
    }

    internal class AutoMapperProfile : Profile
    {
        public AutoMapperProfile()
        {
            CreateStatisticalUnitMap<LegalUnitCreateM, LegalUnit>();

            CreateStatisticalUnitMap<LocalUnitCreateM, LocalUnit>();

            CreateStatisticalUnitMap<EnterpriseUnitCreateM, EnterpriseUnit>()
                .ForMember(x => x.LegalUnits, opt => opt.Ignore())
                .ForMember(x => x.LocalUnits, opt => opt.Ignore());

            CreateMap<Address, AddressM>().ReverseMap();

            CreateMap<EnterpriseGroupCreateM, EnterpriseGroup>(MemberList.None)
                .ForMember(x => x.ChangeReason, x => x.UseValue(ChangeReasons.Create))
                .ForMember(x => x.StartPeriod, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.EndPeriod, x => x.UseValue(DateTime.MaxValue))
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore());

            CreateMap<LegalUnitEditM, LegalUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForAllMembers(v => v.Condition(
                    (src, dst) => src.DataAccess?.Contains($"{dst.GetType().Name}.{v.DestinationMember.Name}") ?? false
                ));
            CreateMap<LocalUnitEditM, LocalUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForAllMembers(v => v.Condition(
                    (src, dst) => src.DataAccess?.Contains($"{dst.GetType().Name}.{v.DestinationMember.Name}") ?? false
                ));
            CreateMap<EnterpriseUnitEditM, EnterpriseUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.LocalUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForAllMembers(v => v.Condition(
                    (src, dst) => src.DataAccess?.Contains($"{dst.GetType().Name}.{v.DestinationMember.Name}") ?? false
                ));
            
            CreateMap<EnterpriseGroupEditM, EnterpriseGroup>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore());

            CreateMap<ActivityM, Activity>()
                .ForMember(x => x.Id, x => x.Ignore())
                .ForMember(x => x.UpdatedDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.ActivityRevxCategory, x => x.Ignore());

            CreateMap<AddressModel, Address>().ReverseMap();
            CreateMap<SoateModel, Soate>().ReverseMap();

            ConfigureLookups();
            HistoryMaping();
        }

        private void ConfigureLookups()
        {
            CreateMap<EnterpriseUnit, LookupVm>()
                .ForMember(x => x.Id, opt => opt.MapFrom(x => x.RegId))
                .ForMember(x => x.Name, opt => opt.MapFrom(x => x.Name));
            
            CreateMap<EnterpriseGroup, LookupVm>()
                .ForMember(x => x.Id, opt => opt.MapFrom(x => x.RegId))
                .ForMember(x => x.Name, opt => opt.MapFrom(x => x.Name));

            CreateMap<LocalUnit, LookupVm>()
                .ForMember(x => x.Id, opt => opt.MapFrom(x => x.RegId))
                .ForMember(x => x.Name, opt => opt.MapFrom(x => x.Name));

            CreateMap<LegalUnit, LookupVm>()
                .ForMember(x => x.Id, opt => opt.MapFrom(x => x.RegId))
                .ForMember(x => x.Name, opt => opt.MapFrom(x => x.Name));

        }

        private void HistoryMaping()
        {
            MapStatisticalUnit<LegalUnit>();
            MapStatisticalUnit<LocalUnit>();
            MapStatisticalUnit<EnterpriseUnit>();
            CreateMap<EnterpriseGroup, EnterpriseGroup>();
        }
        
        private void MapStatisticalUnit<T>() where T : StatisticalUnit
        {
            CreateMap<T, T>()
                .ForMember(v => v.Activities, v => v.Ignore())
                .ForMember(v => v.ActivitiesUnits,
                v => v.MapFrom(
                    x => x.ActivitiesUnits.Select(z => new ActivityStatisticalUnit() {ActivityId = z.ActivityId})
                ));
        }

        private IMappingExpression<TSource, TDestination> CreateStatisticalUnitMap<TSource, TDestination>()
            where TSource : StatUnitModelBase
            where TDestination : StatisticalUnit
        {
            return CreateMap<TSource, TDestination>()
                .ForMember(x => x.ChangeReason, x => x.UseValue(ChangeReasons.Create))
                .ForMember(x => x.StartPeriod, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.EndPeriod, x => x.UseValue(DateTime.MaxValue))
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.ActivitiesUnits, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore());
        }
     }
}