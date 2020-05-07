namespace nscreg.Utilities.Configuration
{
    public class ValidationSettings : ISettings
    {
        public bool ValidateStatIdChecksum { get; set; }
        public bool StatIdUnique { get; set; }
    }
}
