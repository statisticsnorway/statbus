using System;

namespace nscreg.Utilities.Enums
{
    /// <summary>
    /// Action enumeration class
    /// </summary>
    [Flags]
    public enum ActionsEnum
    {
        Create = 1,
        Edit = 2,
        View = 4,
    }
}
