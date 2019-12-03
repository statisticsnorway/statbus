using System;

namespace nscreg.Utilities.Attributes
{
    /// <summary>
    /// Class attribute is not a comparison
    /// </summary>
    [AttributeUsage(AttributeTargets.Property, AllowMultiple = false)]
    public class NotCompare : Attribute
    {
    }
}
