using System;

namespace nscreg.Utilities.Enums
{
    /// <summary>
    /// Класс перечисления действий
    /// </summary>
    [Flags]
    public enum ActionsEnum
    {
        Create = 1,
        Edit = 2,
        View = 4,
    }
}
