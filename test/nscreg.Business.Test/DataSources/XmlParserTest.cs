using System.Linq;
using System.Xml.Linq;
using nscreg.Business.DataSources;
using Xunit;

namespace nscreg.Business.Test.DataSources
{
    public class XmlParserTest
    {
        [Fact]
        private void ParseRawEntityTest()
        {
            var xdoc = XDocument.Parse(
                "<TaxPayer>"
                + "<NscCode>21878385</NscCode>"
                + "<Tin>21904196910047</Tin>"
                + "<AddressObl>Чуйская обл., Аламудунский р-н, Степное</AddressObl>"
                + "<AddressStreet>ул.Артезиан 23</AddressStreet>"
                + "<FullName>Балабеков Ибрахим Хакиевич</FullName>"
                + "<CoateCode>41708203859030</CoateCode>"
                + "<AwardingSolutionDate>2016-08-10T00:00:00+06:00</AwardingSolutionDate>"
                + "<LiquidationReasonCode>003</LiquidationReasonCode>"
                + "<OSNOVAN>Реш.суда -неплатежесп.(банкротства)</OSNOVAN>" +
                "</TaxPayer>"
            );

            var actual = XmlParser.ParseRawEntity(xdoc.Root);

            Assert.Equal(9, actual.Count);
            Assert.Equal("21878385", actual["NscCode"]);
            Assert.Equal("21904196910047", actual["Tin"]);
            Assert.Equal("Балабеков Ибрахим Хакиевич", actual["FullName"]);
        }

        [Fact]
        private void GetRawEntitiesTest()
        {
            var xdoc = XDocument.Parse(
                "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
                "<GetTaxPayersLiquidatedResult xmlns=\"http://sti.gov.kg/\">" +
                "<TaxPayer>"
                + "<NscCode>21878385</NscCode>"
                + "<Tin>21904196910047</Tin>"
                + "<AddressObl>Чуйская обл., Аламудунский р-н, Степное</AddressObl>"
                + "<AddressStreet>ул.Артезиан 23</AddressStreet>"
                + "<FullName>Балабеков Ибрахим Хакиевич</FullName>"
                + "<CoateCode>41708203859030</CoateCode>"
                + "<AwardingSolutionDate>2016-08-10T00:00:00+06:00</AwardingSolutionDate>"
                + "<LiquidationReasonCode>003</LiquidationReasonCode>"
                + "<OSNOVAN>Реш.суда -неплатежесп.(банкротства)</OSNOVAN>" +
                "</TaxPayer>" +
                "<TaxPayer>"
                + "<NscCode>22987099</NscCode>"
                + "<Tin>10510196100229</Tin>"
                + "<AddressObl>Таласская обл., Карабуринский р-н, Кызыл-адыр</AddressObl>"
                + "<AddressStreet>ул. Аларча 19</AddressStreet>"
                + "<FullName>Искендерова Алтынкул Убайдылдаевна</FullName>"
                + "<CoateCode>41707215818010</CoateCode>"
                + "<AwardingSolutionDate>2016-09-06T00:00:00+06:00</AwardingSolutionDate>"
                + "<LiquidationReasonCode>001</LiquidationReasonCode>"
                + "<OSNOVAN>Реш,собств-ка/органа, уполн-го собс-ком</OSNOVAN>" +
                "</TaxPayer>" +
                "</GetTaxPayersLiquidatedResult>"
            );

            var actual = XmlParser.GetRawEntities(xdoc).ToArray();

            Assert.Equal(2, actual.Length);
            Assert.Equal("TaxPayer", actual[0].Name.LocalName);
            Assert.Equal(9, actual[0].Descendants().Count());

            // two xml-related methods integration test - temporary solution, while other logic is unclear
            var entitiesDictionary = actual.Select(XmlParser.ParseRawEntity).ToArray();
            Assert.Equal(2, entitiesDictionary.Length);
            Assert.True(entitiesDictionary.All(dict => dict.Count == 9));
        }
    }
}
