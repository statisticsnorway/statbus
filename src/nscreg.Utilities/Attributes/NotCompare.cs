using System;

namespace nscreg.Utilities.Attributes
{
    /// <summary>
    /// Класс атрибут не сравнения
    /// </summary>
    [AttributeUsage(AttributeTargets.Property, AllowMultiple = false)]
    public class NotCompare : Attribute
    {
    }
}
