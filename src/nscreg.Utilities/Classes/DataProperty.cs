using System.Reflection;

namespace nscreg.Utilities.Classes
{
    internal class DataProperty<T> : GenericDataProperty<T, object>
    {
        public DataProperty(PropertyInfo property) : base(property) { }
    }
}