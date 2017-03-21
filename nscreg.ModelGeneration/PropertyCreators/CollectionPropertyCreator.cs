using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;

namespace nscreg.ModelGeneration.PropertyCreators
{
//    public class CollectionPropertyCreator : PropertyCreatorBase
//    {
//        public override bool CanCreate(PropertyInfo propInfo)
//        {
//            var type = propInfo.PropertyType;
//            return type.GetTypeInfo().IsGenericType
//                   && type.GetGenericTypeDefinition() == typeof(ICollection<>)
//                   && !type.GenericTypeArguments[0].GetTypeInfo().IsPrimitive;
//        }
//
//        public override PropertyMetadataBase Create(PropertyInfo propInfo, object obj)
//        {
//            return new CollectionPropertyMetadata();
//           /* propInfo.Name
//                !propInfo.PropertyType.IsNullable(),
//                GetAtomicValue<DateTime?>(propInfo, obj));*/
//        }
//    }
}
