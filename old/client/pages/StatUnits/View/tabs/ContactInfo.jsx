import React from 'react'
import { shape, func, string, number, oneOfType, arrayOf } from 'prop-types'
import { Label, Grid, Header, Segment } from 'semantic-ui-react'

import { PersonsList } from '/components/fields'
import { hasValue } from '/helpers/validation'
import { getNewName } from '/helpers/locale'
import styles from './styles.scss'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { library } from '@fortawesome/fontawesome-svg-core'
import { faCircleChevronRight, faCircleChevronDown } from '@fortawesome/free-solid-svg-icons'

export class ContactInfo extends React.Component {
  constructor(props) {
    library.add(faCircleChevronRight)
    library.add(faCircleChevronDown)
    super(props)
    this.state = {
      postalAddressIsChecked: false,
    }
  }

  static propTypes = {
    data: shape({
      emailAddress: string,
      telephoneNo: oneOfType([string, number]),
      actualAddress: shape({}),
      persons: arrayOf(shape({})),
    }).isRequired,
    localize: func.isRequired,
    activeTab: string.isRequired,
  }

  toggleCollapse = () => {
    this.setState(prevState => ({ postalAddressIsChecked: !prevState.postalAddressIsChecked }))
  }

  render() {
    const { localize, data, activeTab } = this.props
    const { postalAddressIsChecked } = this.state

    let regions = []
    let region = data.actualAddress ? data.actualAddress.region : null
    while (region) {
      regions.push(getNewName({
        name: region.name,
        code: region.code,
        nameLanguage1: region.nameLanguage1,
        nameLanguage2: region.nameLanguage2,
      }))
      region = region.parent
    }
    regions = regions.reverse()
    regions = regions.map((regionName, index) => ({
      name: regionName,
      levelName: localize(`RegionLvl${index + 1}`),
    }))
    return (
      <div>
        {activeTab !== 'contactInfo' && (
          <Header as="h5" className={styles.heigthHeader} content={localize('ContactInfo')} />
        )}
        <Segment>
          <Grid divided columns={2}>
            <Grid.Row>
              <Grid.Column width={5}>
                <div className={styles.container}>
                  <label className={styles.boldText}>{localize('TelephoneNo')}</label>
                  <Label
                    className={styles[`${data.telephoneNo ? 'labelStyle' : 'emptyLabel'}`]}
                    basic
                    size="large"
                  >
                    {data.telephoneNo}
                  </Label>
                </div>
              </Grid.Column>
              <Grid.Column width={5}>
                <div className={styles.container}>
                  <label className={styles.boldText}>{localize('EmailAddress')}</label>
                  <Label
                    className={styles[`${data.emailAddress ? 'labelStyle' : 'emptyLabel'}`]}
                    basic
                    size="large"
                  >
                    {data.emailAddress}
                  </Label>
                </div>
              </Grid.Column>
            </Grid.Row>
            <Grid.Row>
              <Grid.Column width={8}>
                <Header as="h5" content={localize('VisitingAddress')} dividing />
                <Grid doubling padded>
                  <Grid.Row verticalAlign="middle">
                    <Grid.Column width={6} className={styles.columnMargin}>
                      <label className={styles.boldText}>{localize('Region')}</label>
                    </Grid.Column>
                    <Grid.Column width={10} className={styles.columnMargin}>
                      <Label
                        className={
                          styles[
                            `${
                              data.actualAddress && data.actualAddress.region
                                ? 'labelStyle'
                                : 'emptyLabel'
                            }`
                          ]
                        }
                        basic
                        size="large"
                      >
                        {data.actualAddress &&
                          hasValue(data.actualAddress.region) &&
                          getNewName(data.actualAddress.region)}
                      </Label>
                    </Grid.Column>
                    <Grid.Column width={6} className={styles.columnMargin}>
                      <label className={styles.boldText}>{localize('AddressPart1')}</label>
                    </Grid.Column>
                    <Grid.Column width={10} className={styles.columnMargin}>
                      <Label
                        className={
                          styles[
                            `${
                              data.actualAddress && data.actualAddress.addressPart1
                                ? 'labelStyle'
                                : 'emptyLabel'
                            }`
                          ]
                        }
                        basic
                        size="large"
                      >
                        {data.actualAddress && data.actualAddress.addressPart1}
                      </Label>
                    </Grid.Column>
                    <Grid.Column width={6} className={styles.columnMargin}>
                      <label className={styles.boldText}>{localize('AddressPart2')}</label>
                    </Grid.Column>
                    <Grid.Column width={10} className={styles.columnMargin}>
                      <Label
                        className={
                          styles[
                            `${
                              data.actualAddress && data.actualAddress.addressPart2
                                ? 'labelStyle'
                                : 'emptyLabel'
                            }`
                          ]
                        }
                        basic
                        size="large"
                      >
                        {data.actualAddress && data.actualAddress.addressPart2}
                      </Label>
                    </Grid.Column>
                    <Grid.Column width={6} className={styles.columnMargin}>
                      <label className={styles.boldText}>{localize('AddressPart3')}</label>
                    </Grid.Column>
                    <Grid.Column width={10} className={styles.columnMargin}>
                      <Label
                        className={
                          styles[
                            `${
                              data.actualAddress && data.actualAddress.addressPart3
                                ? 'labelStyle'
                                : 'emptyLabel'
                            }`
                          ]
                        }
                        basic
                        size="large"
                      >
                        {data.actualAddress && data.actualAddress.addressPart3}
                      </Label>
                    </Grid.Column>
                    <Grid.Column width={16}>
                      <Segment>
                        <Header as="h5" content={localize('GpsCoordinates')} dividing />
                        <Grid doubling>
                          <Grid.Row verticalAlign="middle">
                            <Grid.Column width={6} className={styles.columnMargin}>
                              <label className={styles.boldText}>{localize('Latitude')}</label>
                            </Grid.Column>
                            <Grid.Column width={10} className={styles.columnMargin}>
                              <Label
                                className={
                                  styles[
                                    `${
                                      data.address && data.address.latitude
                                        ? 'labelStyle'
                                        : 'emptyLabel'
                                    }`
                                  ]
                                }
                                basic
                                size="large"
                              >
                                {data.address &&
                                  hasValue(data.address.latitude) &&
                                  data.address.latitude}
                              </Label>
                            </Grid.Column>
                            <Grid.Column width={6} className={styles.columnMargin}>
                              <label className={styles.boldText}>{localize('Longitude')}</label>
                            </Grid.Column>
                            <Grid.Column width={10} className={styles.columnMargin}>
                              <Label
                                className={
                                  styles[
                                    `${
                                      data.address && data.address.longitude
                                        ? 'labelStyle'
                                        : 'emptyLabel'
                                    }`
                                  ]
                                }
                                basic
                                size="large"
                              >
                                {data.address &&
                                  hasValue(data.address.longitude) &&
                                  data.address.longitude}
                              </Label>
                            </Grid.Column>
                          </Grid.Row>
                        </Grid>
                      </Segment>
                    </Grid.Column>
                  </Grid.Row>
                </Grid>
              </Grid.Column>
              <Grid.Column width={8}>
                <div style={{ display: 'flex', cursor: 'pointer' }} onClick={this.toggleCollapse}>
                  <Header as="h5" content={localize('PostalAddress')} dividing />
                  {!postalAddressIsChecked && (
                    <FontAwesomeIcon icon="circle-chevron-right" style={{ marginLeft: '5px' }} />
                  )}
                  {postalAddressIsChecked && (
                    <FontAwesomeIcon icon="circle-chevron-down" style={{ marginLeft: '5px' }} />
                  )}
                </div>
                {postalAddressIsChecked && (
                  <Grid doubling padded>
                    <Grid.Row verticalAlign="middle">
                      <Grid.Column width={6} className={styles.columnMargin}>
                        <label className={styles.boldText}>{localize('Region')}</label>
                      </Grid.Column>
                      <Grid.Column width={10} className={styles.columnMargin}>
                        <Label
                          className={
                            styles[
                              `${
                                data.postalAddress && data.postalAddress.region
                                  ? 'labelStyle'
                                  : 'emptyLabel'
                              }`
                            ]
                          }
                          basic
                          size="large"
                        >
                          {data.postalAddress &&
                            hasValue(data.postalAddress.region) &&
                            getNewName(data.postalAddress.region)}
                        </Label>
                      </Grid.Column>
                      <Grid.Column width={6} className={styles.columnMargin}>
                        <label className={styles.boldText}>{localize('AddressPart1')}</label>
                      </Grid.Column>
                      <Grid.Column width={10} className={styles.columnMargin}>
                        <Label
                          className={
                            styles[
                              `${
                                data.postalAddress && data.postalAddress.addressPart1
                                  ? 'labelStyle'
                                  : 'emptyLabel'
                              }`
                            ]
                          }
                          basic
                          size="large"
                        >
                          {data.postalAddress && data.postalAddress.addressPart1}
                        </Label>
                      </Grid.Column>
                      <Grid.Column width={6} className={styles.columnMargin}>
                        <label className={styles.boldText}>{localize('AddressPart2')}</label>
                      </Grid.Column>
                      <Grid.Column width={10} className={styles.columnMargin}>
                        <Label
                          className={
                            styles[
                              `${
                                data.postalAddress && data.postalAddress.addressPart2
                                  ? 'labelStyle'
                                  : 'emptyLabel'
                              }`
                            ]
                          }
                          basic
                          size="large"
                        >
                          {data.postalAddress && data.postalAddress.addressPart2}
                        </Label>
                      </Grid.Column>
                      <Grid.Column width={6} className={styles.columnMargin}>
                        <label className={styles.boldText}>{localize('AddressPart3')}</label>
                      </Grid.Column>
                      <Grid.Column width={10} className={styles.columnMargin}>
                        <Label
                          className={
                            styles[
                              `${
                                data.postalAddress && data.postalAddress.addressPart3
                                  ? 'labelStyle'
                                  : 'emptyLabel'
                              }`
                            ]
                          }
                          basic
                          size="large"
                        >
                          {data.postalAddress && data.postalAddress.addressPart3}
                        </Label>
                      </Grid.Column>
                    </Grid.Row>
                  </Grid>
                )}
              </Grid.Column>
            </Grid.Row>
          </Grid>
          <Grid>
            <Grid.Row columns={regions.length > 4 ? regions.length : 4}>
              {regions.map((x, i) => (
                <Grid.Column key={i}>
                  <div className={styles.container}>
                    <label className={styles.boldText}>{x.levelName}</label>
                    <Label basic size="large">
                      <label className={styles.labelRegion}>{x.name}</label>
                    </Label>
                  </div>
                </Grid.Column>
              ))}
            </Grid.Row>
            <Grid.Row>
              <Grid.Column width={16}>
                <label className={styles.boldText}>{localize('PersonsRelatedToTheUnit')}</label>
                <PersonsList name="persons" value={data.persons} localize={localize} readOnly />
              </Grid.Column>
            </Grid.Row>
          </Grid>
        </Segment>
      </div>
    )
  }
}

export default ContactInfo
