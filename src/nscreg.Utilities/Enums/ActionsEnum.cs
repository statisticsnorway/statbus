using System;

namespace nscreg.Utilities.Enums
{
    /// <summary>
    /// Класс перечисления действий
    /// </summary>
    [Flags]
    public enum ActionsEnum
    {
        Create = 0,
        Edit = 1,
        View = 2,
    }
}
