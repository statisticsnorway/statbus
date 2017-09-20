using System.Reflection;

namespace nscreg.Utilities.Classes
{
    /// <summary>
    /// Классс описывающий свойства данных
    /// </summary>
    internal class DataProperty<T> : GenericDataProperty<T, object>
    {
        public DataProperty(PropertyInfo property) : base(property) { }
    }
}
