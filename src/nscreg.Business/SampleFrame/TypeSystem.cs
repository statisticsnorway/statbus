using System;
using System.Collections.Generic;
using System.Reflection;

namespace nscreg.Business.SampleFrame
{
    internal static class TypeSystem
    {
        internal static Type GetElementType(Type seqType)
        {
            var ienum = FindIEnumerable(seqType);
            return ienum == null ? seqType : ienum.GetGenericArguments()[0];
        }

        private static Type FindIEnumerable(Type seqType)
        {
            if (seqType == null || seqType == typeof(string))
                return null;

            if (seqType.IsArray)
                return typeof(IEnumerable<>).MakeGenericType(seqType.GetElementType());

            if (seqType.GetTypeInfo().IsGenericType)
                foreach (var arg in seqType.GetGenericArguments())
                {
                    var ienum = typeof(IEnumerable<>).MakeGenericType(arg);
                    if (ienum.IsAssignableFrom(seqType))
                        return ienum;
                }

            var ifaces = seqType.GetInterfaces();

            if (ifaces != null && ifaces.Length > 0)
                foreach (var iface in ifaces)
                {
                    var ienum = FindIEnumerable(iface);
                    if (ienum != null) return ienum;
                }

            if (seqType.GetTypeInfo().BaseType != null && seqType.GetTypeInfo().BaseType != typeof(object))
                return FindIEnumerable(seqType.GetTypeInfo().BaseType);

            return null;
        }
    }
}
