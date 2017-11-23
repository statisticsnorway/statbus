namespace nscreg.Data.Entities.ComplexTypes
{
    public class Permission
    {
        public Permission(string propertyName, bool canRead, bool canWrite)
        {
            PropertyName = propertyName;
            CanRead = canRead;
            CanWrite = canWrite;
        }

        public Permission()
        {
        }

        public string PropertyName { get; set; }
        public bool CanRead { get; set; }
        public bool CanWrite { get; set; }

    }
}
