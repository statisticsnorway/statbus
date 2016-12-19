using System.Reflection;

namespace nscreg.Utilities
{
    public static class ObjectExtensions
    {
        public static TResult GetValueByIndex<TResult>(this object obj, string propName) => (TResult)obj.GetType().GetProperty(propName).GetValue(obj);
    }
}
