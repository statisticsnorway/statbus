using nscreg.Data.Constants;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace nscreg.DataSources.Service.Services
{
    public class HandleQueueItem
    {
        private readonly StatUnitTypes _type;
        private readonly DataSourceAllowedOperation _operation;
        private readonly DataSourcePriority _priority;
        private readonly string _mapping;
        private readonly string _restrictions;
        private readonly string _rawFile;

        private HandleQueueItem(
            StatUnitTypes type,
            DataSourceAllowedOperation operation,
            DataSourcePriority priority,
            string mapping,
            string restrictions,
            string rawFile
        )
        {
            _type = type;
            _operation = operation;
            _priority = priority;
            _mapping = mapping;
            _restrictions = restrictions;
            _rawFile = rawFile;
        }

        public static async Task<HandleQueueItem> CreateUploadHandler(
            string filePath,
            StatUnitTypes type,
            DataSourceAllowedOperation operation,
            DataSourcePriority priority,
            string mapping,
            string restrictions
            )
        {
            var rawFile = XDocument.Load(filePath);
            foreach (var xelem in rawFile.Root.Elements())
            {

            }
            return new HandleQueueItem(
                type,
                operation,
                priority,
                mapping,
                restrictions,
                rawFile
                );
        }
    }
}
