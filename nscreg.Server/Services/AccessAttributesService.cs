using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Models.DataAccess;

namespace nscreg.Server.Services
{
    public class AccessAttributesService
    {
        public AccessAttributesService(NSCRegDbContext context)
        {
            DbContext = context;
            ReadCtx = new ReadContext(context);
        }

        private ReadContext ReadCtx { get; }

        private NSCRegDbContext DbContext { get; }

        public IEnumerable<KeyValuePair<int, string>> GetAllSystemFunctions()
            => ((SystemFunctions[]) Enum.GetValues(typeof(SystemFunctions)))
                .Select(x => new KeyValuePair<int, string>((int) x, x.ToString()));

        public IEnumerable<string> GetAllDataAttributes()
            =>
                GetProperties<StatisticalUnit>();

        private static string[] GetProperties<T>() => typeof(T).GetProperties().Select(x => x.Name).ToArray();

        public DataAccessModel GetAllDataAccessAttributes()
        {
            return DataAccessModel.FromString();
        }

        public DataAccessModel GetAllDataAccessAttributesByUser(string userId)
        {
            var user = ReadCtx.Users.Single(x => x.Id == userId);
            return DataAccessModel.FromString(user.DataAccess);
        }

        public DataAccessModel GetAllDataAccessAttributesByRole(string roleId)
        {
            var role = ReadCtx.Roles.Single(x => x.Id == roleId);
            return DataAccessModel.FromString(role.StandardDataAccess);
        }
    }
}