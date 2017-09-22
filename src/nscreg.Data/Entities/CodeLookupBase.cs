using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность базовый справочник кода
    /// </summary>
    public class CodeLookupBase : LookupBase
    {
        public string Code { get; set; }
    }
}
