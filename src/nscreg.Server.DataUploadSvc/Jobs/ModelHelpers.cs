using AutoMapper;
using nscreg.Data.Entities;

namespace nscreg.Server.DataUploadSvc.Jobs
{
    internal static class ModelHelpers
    {
        public static TModel MapUnitTo<TModel>(IStatisticalUnit unit) => Mapper.Map<TModel>(unit);
    }
}
