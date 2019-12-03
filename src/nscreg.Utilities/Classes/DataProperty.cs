using System.Reflection;

namespace nscreg.Utilities.Classes
{
    /// <summary>
    /// Classes describing data properties
    /// </summary>
    internal class DataProperty<T> : GenericDataProperty<T, object>
    {
        public DataProperty(PropertyInfo property) : base(property) { }
    }
}
