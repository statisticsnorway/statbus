using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Utilities
{
    public class StatisticalUnitCreateException : Exception
    {
        public StatisticalUnitCreateException(string message, Exception innerException) : base(message, innerException)
        {
        }
    }
}
