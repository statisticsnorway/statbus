using System;
using System.Linq;
using AutoMapper;
using nscreg.Data.Entities;
using nscreg.Server.Models.Addresses;
using nscreg.Server.Models.DataAccess;
using nscreg.Server.Models.Lookup;
using nscreg.Server.Models.Soates;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Server.Services;
using nscreg.Utilities;
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
            DataAccessCondition(
                CreateStatisticalUnitMap<LegalUnitCreateM, LegalUnit>()
                    .ForMember(x => x.LocalUnits, x => x.Ignore())
            );

            DataAccessCondition(
                CreateStatisticalUnitMap<LocalUnitCreateM, LocalUnit>()
            );

            DataAccessCondition(
                CreateStatisticalUnitMap<EnterpriseUnitCreateM, EnterpriseUnit>()
                    .ForMember(x => x.LegalUnits, opt => opt.Ignore())
                    .ForMember(x => x.LocalUnits, opt => opt.Ignore())
            );

            CreateMap<Address, AddressM>().ReverseMap();

            DataAccessCondition(
                CreateMap<EnterpriseGroupCreateM, EnterpriseGroup>(MemberList.None)
                    .ForMember(x => x.ChangeReason, x => x.UseValue(ChangeReasons.Create))
                    .ForMember(x => x.StartPeriod, x => x.UseValue(DateTime.Now))
                    .ForMember(x => x.EndPeriod, x => x.UseValue(DateTime.MaxValue))
                    .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                    .ForMember(x => x.Address, x => x.Ignore())
                    .ForMember(x => x.ActualAddress, x => x.Ignore())
                    .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                    .ForMember(x => x.LegalUnits, opt => opt.Ignore())
            );

            DataAccessCondition(
                CreateMap<LegalUnitEditM, LegalUnit>()
                    .ForMember(x => x.Address, x => x.Ignore())
                    .ForMember(x => x.ActualAddress, x => x.Ignore())
                    .ForMember(x => x.Activities, x => x.Ignore())
                    .ForMember(x => x.LocalUnits, x => x.Ignore())
            );

            DataAccessCondition(
                CreateMap<LocalUnitEditM, LocalUnit>()
                    .ForMember(x => x.Address, x => x.Ignore())
                    .ForMember(x => x.ActualAddress, x => x.Ignore())
                    .ForMember(x => x.Activities, x => x.Ignore())
            );

            DataAccessCondition(
                CreateMap<EnterpriseUnitEditM, EnterpriseUnit>()
                    .ForMember(x => x.Address, x => x.Ignore())
                    .ForMember(x => x.ActualAddress, x => x.Ignore())
                    .ForMember(x => x.LocalUnits, opt => opt.Ignore())
                    .ForMember(x => x.LegalUnits, opt => opt.Ignore())
                    .ForMember(x => x.Activities, x => x.Ignore())
            );

            DataAccessCondition(
                CreateMap<EnterpriseGroupEditM, EnterpriseGroup>()
                    .ForMember(x => x.Address, x => x.Ignore())
                    .ForMember(x => x.ActualAddress, x => x.Ignore())
                    .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                    .ForMember(x => x.LegalUnits, opt => opt.Ignore())
            );

            CreateMap<ActivityM, Activity>()
                .ForMember(x => x.Id, x => x.Ignore())
                .ForMember(x => x.UpdatedDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.ActivityRevxCategory, x => x.Ignore());

            CreateMap<AddressModel, Address>().ReverseMap();
            CreateMap<SoateModel, Soate>().ReverseMap();

            CreateMap<CodeLookupVm, UnitLookupVm>();
            CreateMap<DataAccessAttributeM, DataAccessAttributeVm>();

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
            MapStatisticalUnit<LocalUnit>();
            MapStatisticalUnit<LegalUnit>()
                .ForMember(m => m.LocalUnits, m => m.Ignore());
            MapStatisticalUnit<EnterpriseUnit>()
              .ForMember(m => m.LegalUnits, m => m.Ignore())
              .ForMember(m => m.LocalUnits, m => m.Ignore())
                ;
            CreateMap<EnterpriseGroup, EnterpriseGroup>()
                .ForMember(m => m.EnterpriseUnits, m => m.Ignore());
        }
        
        private IMappingExpression<T, T> MapStatisticalUnit<T>() where T : StatisticalUnit
        {
            return CreateMap<T, T>()
                .ForMember(v => v.RegId, v => v.UseValue(0))
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

        private void DataAccessCondition<TSource, TDestionation>(IMappingExpression<TSource, TDestionation> mapping) where TSource: IStatUnitM where TDestionation: IStatisticalUnit
        {
          
            mapping.ForAllMembers(v => v.Condition((src, dst) =>
            {
                var name = DataAccessAttributesHelper.GetName(dst.GetType(), v.DestinationMember.Name);
                return DataAccessAttributesProvider.Find(name) == null || (src.DataAccess?.Contains(name) ?? false);
            }));
        }
     }
}