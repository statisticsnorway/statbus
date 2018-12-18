import React from 'react'
import { shape, func, string, number, oneOfType, arrayOf } from 'prop-types'
import { Label, Grid, Header, Segment } from 'semantic-ui-react'

import { PersonsField } from 'components/fields'
import { hasValue } from 'helpers/validation'
import { getNewName } from 'helpers/locale'
import styles from './styles.pcss'

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

  render() {
    const { localize, data, activeTab } = this.props
    let regions = []
    let region = data.address ? data.address.region : null
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
              <Grid.Column width={8}>
                <Header as="h5" content={localize('VisitingAddress')} dividing />
                <Grid doubling>
                  <Grid.Row>
                    <React.Fragment>
                      <Grid.Column width={6}>
                        <label className={styles.boldText}>{localize('Region')}</label>
                      </Grid.Column>
                      <Grid.Column width={10}>
                        <Label className={styles.labelStyle} basic size="large">
                          {`${hasValue(data.actualAddress) &&
                            hasValue(data.actualAddress.region) &&
                            getNewName(data.actualAddress.region)}`}
                        </Label>
                        <br />
                        <br />
                      </Grid.Column>
                    </React.Fragment>
                    <React.Fragment>
                      <Grid.Column width={6}>
                        <label className={styles.boldText}>{localize('AddressPart1')}</label>
                      </Grid.Column>
                      <Grid.Column width={10}>
                        <Label className={styles.labelStyle} basic size="large">
                          {hasValue(data.actualAddress) && data.actualAddress.addressPart1}
                        </Label>
                        <br />
                        <br />
                      </Grid.Column>
                    </React.Fragment>
                    <React.Fragment>
                      <Grid.Column width={6}>
                        <label className={styles.boldText}>{localize('AddressPart2')}</label>
                      </Grid.Column>
                      <Grid.Column width={10}>
                        <Label className={styles.labelStyle} basic size="large">
                          {hasValue(data.actualAddress) && data.actualAddress.addressPart2}
                        </Label>
                        <br />
                        <br />
                      </Grid.Column>
                    </React.Fragment>
                  </Grid.Row>
                </Grid>
              </Grid.Column>
              <Grid.Column width={8}>
                <Header as="h5" content={localize('PostalAddress')} dividing />
                <Grid doubling>
                  <Grid.Row>
                    <React.Fragment>
                      <Grid.Column width={6}>
                        <label className={styles.boldText}>{localize('Region')}</label>
                      </Grid.Column>
                      <Grid.Column width={10}>
                        <Label className={styles.labelStyle} basic size="large">
                          {`${hasValue(data.postalAddress) &&
                            getNewName(data.postalAddress.region)}`}
                        </Label>
                        <br />
                        <br />
                      </Grid.Column>
                    </React.Fragment>
                    <React.Fragment>
                      <Grid.Column width={6}>
                        <label className={styles.boldText}>{localize('AddressPart1')}</label>
                      </Grid.Column>
                      <Grid.Column width={10}>
                        <Label className={styles.labelStyle} basic size="large">
                          {hasValue(data.postalAddress) && data.postalAddress.addressPart1}
                        </Label>
                        <br />
                        <br />
                      </Grid.Column>
                    </React.Fragment>
                    <React.Fragment>
                      <Grid.Column width={6}>
                        <label className={styles.boldText}>{localize('AddressPart2')}</label>
                      </Grid.Column>
                      <Grid.Column width={10}>
                        <Label className={styles.labelStyle} basic size="large">
                          {hasValue(data.postalAddress) && data.postalAddress.addressPart2}
                        </Label>
                        <br />
                        <br />
                      </Grid.Column>
                    </React.Fragment>
                  </Grid.Row>
                </Grid>
              </Grid.Column>
              <Grid.Column width={8}>
                <Header as="h5" content={localize('AsRegistered')} dividing />
                <Grid doubling>
                  <Grid.Row>
                    <React.Fragment>
                      <Grid.Column width={6}>
                        <label className={styles.boldText}>{localize('Region')}</label>
                      </Grid.Column>
                      <Grid.Column width={10}>
                        <Label className={styles.labelStyle} basic size="large">
                          {`${hasValue(data.address) &&
                            hasValue(data.address.region) &&
                            getNewName(data.address.region)}`}
                        </Label>
                        <br />
                        <br />
                      </Grid.Column>
                    </React.Fragment>
                    <React.Fragment>
                      <Grid.Column width={6}>
                        <label className={styles.boldText}>{localize('AddressPart1')}</label>
                      </Grid.Column>
                      <Grid.Column width={10}>
                        <Label className={styles.labelStyle} basic size="large">
                          {hasValue(data.address) && data.address.addressPart1}
                        </Label>
                        <br />
                        <br />
                      </Grid.Column>
                    </React.Fragment>
                    <React.Fragment>
                      <Grid.Column width={6}>
                        <label className={styles.boldText}>{localize('AddressPart2')}</label>
                      </Grid.Column>
                      <Grid.Column width={10}>
                        <Label className={styles.labelStyle} basic size="large">
                          {hasValue(data.address) && data.address.addressPart2}
                        </Label>
                        <br />
                        <br />
                      </Grid.Column>
                    </React.Fragment>
                    <Grid.Column width={16}>
                      <Segment>
                        <Header as="h5" content={localize('GpsCoordinates')} dividing />
                        <Grid doubling>
                          <Grid.Row>
                            <React.Fragment>
                              <Grid.Column width={6}>
                                <label className={styles.boldText}>{localize('Latitude')}</label>
                              </Grid.Column>
                              <Grid.Column width={10}>
                                <Label className={styles.labelStyle} basic size="large">
                                  {hasValue(data.address) && data.address.latitude}
                                </Label>
                                <br />
                                <br />
                              </Grid.Column>
                            </React.Fragment>
                            <React.Fragment>
                              <Grid.Column width={6}>
                                <label className={styles.boldText}>{localize('Longitude')}</label>
                              </Grid.Column>
                              <Grid.Column width={10}>
                                <Label className={styles.labelStyle} basic size="large">
                                  {hasValue(data.address) && data.address.longitude}
                                </Label>
                                <br />
                                <br />
                              </Grid.Column>
                            </React.Fragment>
                          </Grid.Row>
                        </Grid>
                      </Segment>
                    </Grid.Column>
                  </Grid.Row>
                </Grid>
              </Grid.Column>
            </Grid.Row>
          </Grid>
          <Grid>
            <Grid.Row>
              <Grid.Column width={5}>
                <div className={styles.container}>
                  <label className={styles.boldText}>{localize('TelephoneNo')}</label>
                  <Label className={styles.labelStyle} basic size="large">
                    {data.telephoneNo}
                  </Label>
                </div>
              </Grid.Column>
              <Grid.Column width={5}>
                <div className={styles.container}>
                  <label className={styles.boldText}>{localize('EmailAddress')}</label>
                  <Label className={styles.labelStyle} basic size="large">
                    {data.emailAddress}
                  </Label>
                </div>
              </Grid.Column>
            </Grid.Row>
            <Grid.Row columns={regions.length > 4 ? regions.length : 4}>
              {regions.map(region => (
                <Grid.Column>
                  <div className={styles.container}>
                    <label className={styles.boldText}>{region.levelName}</label>
                    <Label className={styles.labelStyle} basic size="large">
                      <label className={styles.labelRegion}>{region.name}</label>
                    </Label>
                  </div>
                </Grid.Column>
              ))}
            </Grid.Row>
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
