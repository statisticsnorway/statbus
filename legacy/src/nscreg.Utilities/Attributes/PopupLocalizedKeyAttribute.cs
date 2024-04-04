using System;

namespace nscreg.Utilities.Attributes
{
    [AttributeUsage(AttributeTargets.Property)]
    public class PopupLocalizedKeyAttribute: Attribute
    {
        public PopupLocalizedKeyAttribute(string popupLocalizedKey)
        {
            PopupLocalizedKey = popupLocalizedKey;
        }

        public string PopupLocalizedKey { get; set; }
    }
}
