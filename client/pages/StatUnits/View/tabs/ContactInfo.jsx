import React from 'react'
import { shape, func, string, number, oneOfType, arrayOf } from 'prop-types'
import { Label, Grid, Header, Segment } from 'semantic-ui-react'

import { PersonsField } from 'components/fields'
import { internalRequest } from 'helpers/request'
import { hasValue } from 'helpers/validation'
import styles from './styles.pcss'

const defaultCode = '41700000000000'
const defaultRegionState = { region: { code: '', name: '' } }

class ContactInfo extends React.Component {
  static propTypes = {
    data: shape({
      emailAddress: string,
      telephoneNo: oneOfType([string, number]),
      address: shape({}).isRequired,
      actualAddress: shape({}),
      persons: arrayOf(shape({})),
    }).isRequired,
    localize: func.isRequired,
    activeTab: string.isRequired,
  }

  state = {
    region: { ...this.props.data.address.region } || defaultRegionState,
    regionMenu1: {
      options: [],
      value: '',
      submenu: 'regionMenu2',
      substrRule: { start: 3, end: 5 },
    },
    regionMenu2: {
      options: [],
      value: '',
      submenu: 'regionMenu3',
      substrRule: { start: 5, end: 8 },
    },
    regionMenu3: {
      options: [],
      value: '',
      submenu: 'regionMenu4',
      substrRule: { start: 8, end: 11 },
    },
    regionMenu4: { options: [], value: '', submenu: null, substrRule: { start: 11, end: 14 } },
  }

  componentDidMount() {
    const code = this.state.region !== null ? this.state.region.code : null
    const menu = 'regionMenu'
    for (let i = 1; i <= 4; i++) {
      const substrStart = this.state[`${menu}${i}`].substrRule.start
      const substrEnd = this.state[`${menu}${i}`].substrRule.end
      this.fetchByPartCode(
        `${menu}${i}`,
        code.substr(0, substrStart),
        defaultCode.substr(substrEnd),
        `${code.substr(0, substrEnd)}${defaultCode.substr(substrEnd)}`,
      )
    }
  }

  fetchByPartCode = (name, start, end, value) =>
    internalRequest({
      url: '/api/regions/getAreasList',
      queryParams: { start, end },
      method: 'get',
      onSuccess: (result) => {
        this.setState(s => ({
          [name]: {
            ...s[name],
            options: result.map(x => ({ key: x.code, value: x.code, text: x.name })),
            value,
          },
        }))
      },
      onFail: () => {
        this.setState(s => ({
          [name]: {
            ...s.name,
            options: [],
            value: '0',
          },
        }))
      },
    })

  render() {
    const { localize, data, activeTab } = this.props
    const { regionMenu1, regionMenu2, regionMenu3, regionMenu4 } = this.state
    const regions = data.address.region.fullPath.split(',').map(x => x.trim())

    return (
      <div>
        {activeTab !== 'contactInfo' && (
          <Header as="h5" className={styles.heigthHeader} content={localize('ContactInfo')} />
        )}
        <Segment>
          <Grid divided columns={2}>
            <Grid.Row>
              <Grid.Column width={8}>
                {hasValue(data.actualAddress) && (
                  <Header as="h5" content={localize('ActualAddress')} dividing />
                )}
                <Grid doubling>
                  <Grid.Row>
                    {hasValue(data.actualAddress) &&
                      hasValue(data.actualAddress.region) &&
                      hasValue(data.actualAddress.region.fullPath) && (
                        <Grid.Column width={6}>
                          <label className={styles.boldText}>{localize('Region')}</label>
                        </Grid.Column>
                      )}
                    {hasValue(data.actualAddress) &&
                      hasValue(data.actualAddress.region) &&
                      hasValue(data.actualAddress.region.fullPath) && (
                        <Grid.Column width={10}>
                          <Label className={styles.labelStyle} basic size="large">
                            {`${data.actualAddress.region.code} ${
                              data.actualAddress.region.fullPath
                            }`}
                          </Label>
                          <br />
                          <br />
                        </Grid.Column>
                      )}
                    {hasValue(data.actualAddress) &&
                      hasValue(data.actualAddress.addressPart1) && (
                        <Grid.Column width={6}>
                          <label className={styles.boldText}>{localize('AddressPart1')}</label>
                        </Grid.Column>
                      )}
                    {hasValue(data.actualAddress) &&
                      hasValue(data.actualAddress.addressPart1) && (
                        <Grid.Column width={10}>
                          <Label className={styles.labelStyle} basic size="large">
                            {data.actualAddress.addressPart1}
                          </Label>
                          <br />
                          <br />
                        </Grid.Column>
                      )}
                    {hasValue(data.actualAddress) &&
                      hasValue(data.actualAddress.addressPart2) && (
                        <Grid.Column width={6}>
                          <label className={styles.boldText}>{localize('AddressPart2')}</label>
                        </Grid.Column>
                      )}
                    {hasValue(data.actualAddress) &&
                      hasValue(data.actualAddress.addressPart2) && (
                        <Grid.Column width={10}>
                          <Label className={styles.labelStyle} basic size="large">
                            {data.actualAddress.addressPart2}
                          </Label>
                          <br />
                          <br />
                        </Grid.Column>
                      )}
                  </Grid.Row>
                </Grid>
              </Grid.Column>

              <Grid.Column width={8}>
                {hasValue(data.postalAddress) && (
                  <Header as="h5" content={localize('PostalAddress')} dividing />
                )}
                <Grid doubling>
                  <Grid.Row>
                    {hasValue(data.postalAddress) &&
                      hasValue(data.postalAddress.region) &&
                      hasValue(data.postalAddress.region.fullPath) && (
                        <Grid.Column width={6}>
                          <label className={styles.boldText}>{localize('Region')}</label>
                        </Grid.Column>
                      )}
                    {hasValue(data.postalAddress) &&
                      hasValue(data.postalAddress.region) &&
                      hasValue(data.postalAddress.region.fullPath) && (
                        <Grid.Column width={10}>
                          <Label className={styles.labelStyle} basic size="large">
                            {`${data.postalAddress.region.code} ${
                              data.postalAddress.region.fullPath
                            }`}
                          </Label>
                          <br />
                          <br />
                        </Grid.Column>
                      )}
                    {hasValue(data.postalAddress) &&
                      hasValue(data.postalAddress.addressPart1) && (
                        <Grid.Column width={6}>
                          <label className={styles.boldText}>{localize('AddressPart1')}</label>
                        </Grid.Column>
                      )}
                    {hasValue(data.postalAddress) &&
                      hasValue(data.postalAddress.addressPart1) && (
                        <Grid.Column width={10}>
                          <Label className={styles.labelStyle} basic size="large">
                            {data.postalAddress.addressPart1}
                          </Label>
                          <br />
                          <br />
                        </Grid.Column>
                      )}
                    {hasValue(data.postalAddress) &&
                      hasValue(data.postalAddress.addressPart2) && (
                        <Grid.Column width={6}>
                          <label className={styles.boldText}>{localize('AddressPart2')}</label>
                        </Grid.Column>
                      )}
                    {hasValue(data.postalAddress) &&
                      hasValue(data.postalAddress.addressPart2) && (
                        <Grid.Column width={10}>
                          <Label className={styles.labelStyle} basic size="large">
                            {data.postalAddress.addressPart2}
                          </Label>
                          <br />
                          <br />
                        </Grid.Column>
                      )}
                  </Grid.Row>
                </Grid>
              </Grid.Column>
              <Grid.Column width={8}>
                <Header as="h5" content={localize('AsRegistered')} dividing />
                <Grid doubling>
                  <Grid.Row>
                    {hasValue(data.address) &&
                      hasValue(data.address.region) &&
                      hasValue(data.address.region.fullPath) && (
                        <Grid.Column width={6}>
                          <label className={styles.boldText}>{localize('Region')}</label>
                        </Grid.Column>
                      )}
                    {hasValue(data.address) &&
                      hasValue(data.address.region) &&
                      hasValue(data.address.region.fullPath) && (
                        <Grid.Column width={10}>
                          <Label className={styles.labelStyle} basic size="large">
                            {`${data.address.region.code} ${data.address.region.fullPath}`}
                          </Label>
                          <br />
                          <br />
                        </Grid.Column>
                      )}

                    {hasValue(data.address) &&
                      hasValue(data.address.addressPart1) && (
                        <Grid.Column width={6}>
                          <label className={styles.boldText}>{localize('AddressPart1')}</label>
                        </Grid.Column>
                      )}
                    {hasValue(data.address) &&
                      hasValue(data.address.addressPart1) && (
                        <Grid.Column width={10}>
                          <Label className={styles.labelStyle} basic size="large">
                            {data.address.addressPart1}
                          </Label>
                          <br />
                          <br />
                        </Grid.Column>
                      )}
                    {hasValue(data.address) &&
                      hasValue(data.address.addressPart2) && (
                        <Grid.Column width={6}>
                          <label className={styles.boldText}>{localize('AddressPart2')}</label>
                        </Grid.Column>
                      )}
                    {hasValue(data.address) &&
                      hasValue(data.address.addressPart2) && (
                        <Grid.Column width={10}>
                          <Label className={styles.labelStyle} basic size="large">
                            {data.address.addressPart2}
                          </Label>
                          <br />
                          <br />
                        </Grid.Column>
                      )}
                    <Grid.Column width={16}>
                      {(hasValue(data.address) &&
                        hasValue(data.address.latitude) &&
                        data.address.latitude != 0) ||
                      (hasValue(data.address) &&
                        hasValue(data.address.longitude) &&
                        data.address.longitude != 0) ? (
                          <Segment>
                            <Header as="h5" content={localize('GpsCoordinates')} dividing />
                            <Grid doubling>
                              <Grid.Row>
                                {hasValue(data.address) &&
                                hasValue(data.address.latitude) &&
                                data.address.latitude != 0 && (
                                  <Grid.Column width={6}>
                                    <label className={styles.boldText}>
                                      {localize('Latitude')}
                                    </label>
                                  </Grid.Column>
                                )}
                                {hasValue(data.address) &&
                                hasValue(data.address.latitude) &&
                                data.address.latitude != 0 && (
                                  <Grid.Column width={10}>
                                    <Label className={styles.labelStyle} basic size="large">
                                      {data.address.latitude}
                                    </Label>
                                    <br />
                                    <br />
                                  </Grid.Column>
                                )}
                                {hasValue(data.address) &&
                                hasValue(data.address.longitude) &&
                                data.address.longitude != 0 && (
                                  <Grid.Column width={6}>
                                    <label className={styles.boldText}>
                                      {localize('Longitude')}
                                    </label>
                                  </Grid.Column>
                                )}
                                {hasValue(data.address) &&
                                hasValue(data.address.longitude) &&
                                data.address.longitude != 0 && (
                                  <Grid.Column width={10}>
                                    <Label className={styles.labelStyle} basic size="large">
                                      {data.address.longitude}
                                    </Label>
                                    <br />
                                    <br />
                                  </Grid.Column>
                                )}
                              </Grid.Row>
                            </Grid>
                          </Segment>
                      ) : (
                        <div />
                      )}
                    </Grid.Column>
                  </Grid.Row>
                </Grid>
              </Grid.Column>
            </Grid.Row>
          </Grid>
          <br />
          <br />
          <Grid>
            <Grid.Row>
              {data.telephoneNo && (
                <Grid.Column width={5}>
                  <div className={styles.container}>
                    <label className={styles.boldText}>{localize('TelephoneNo')}</label>
                    <Label className={styles.labelStyle} basic size="large">
                      {data.telephoneNo}
                    </Label>
                  </div>
                </Grid.Column>
              )}
              {data.emailAddress && (
                <Grid.Column width={5}>
                  <div className={styles.container}>
                    <label className={styles.boldText}>{localize('EmailAddress')}</label>
                    <Label className={styles.labelStyle} basic size="large">
                      {data.emailAddress}
                    </Label>
                  </div>
                </Grid.Column>
              )}
            </Grid.Row>
            <br />
            <Grid.Row columns={4}>
              {hasValue(regions[0]) && (
                <Grid.Column>
                  <div className={styles.container}>
                    <label className={styles.boldText}>{localize('RegionLvl1')}</label>
                    <Label className={styles.labelStyle} basic size="large">
                      <label className={styles.labelRegion}>{regions[0]}</label>
                      {regionMenu1.value}
                    </Label>
                  </div>
                </Grid.Column>
              )}
              {hasValue(regions[1]) && (
                <Grid.Column>
                  <div className={styles.container}>
                    <label className={styles.boldText}>{localize('RegionLvl2')}</label>
                    <Label className={styles.labelStyle} basic size="large">
                      <label className={styles.labelRegion}>{regions[1]}</label>
                      {regionMenu2.value}
                    </Label>
                  </div>
                </Grid.Column>
              )}
              {hasValue(regions[2]) && (
                <Grid.Column>
                  <div className={styles.container}>
                    <label className={styles.boldText}>{localize('RegionLvl3')}</label>
                    <Label className={styles.labelStyle} basic size="large">
                      <label className={styles.labelRegion}>{regions[2]}</label>
                      {regionMenu3.value}
                    </Label>
                  </div>
                </Grid.Column>
              )}
              {hasValue(regions[3]) && (
                <Grid.Column>
                  <div className={styles.container}>
                    <label className={styles.boldText}>{localize('RegionLvl4')}</label>
                    <Label className={styles.labelStyle} basic size="large">
                      <label className={styles.labelRegion}>{regions[3]}</label>
                      {regionMenu4.value}
                    </Label>
                  </div>
                </Grid.Column>
              )}
            </Grid.Row>
            <br />
            <Grid.Row>
              <Grid.Column width={16}>
                <label className={styles.boldText}>{localize('PersonsRelatedToTheUnit')}</label>
                <PersonsField name="persons" value={data.persons} localize={localize} readOnly />
              </Grid.Column>
            </Grid.Row>
          </Grid>
        </Segment>
      </div>
    )
  }
}

export default ContactInfo
