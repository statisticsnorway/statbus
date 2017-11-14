import React from 'react'
import { shape, func, string, number, oneOfType, arrayOf } from 'prop-types'
import { Label, Grid } from 'semantic-ui-react'

import PersonsGrid from 'components/fields/PersonsField'
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
      persons: arrayOf(shape({})).isRequired,
    }).isRequired,
    localize: func.isRequired,
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
    const { localize, data } = this.props
    const { regionMenu1, regionMenu2, regionMenu3, regionMenu4 } = this.state
    return (
      <div>
        <Grid divided columns={2}>
          <Grid.Row>
            <Grid.Column width={8}>
              <Grid doubling>
                <Grid.Row>
                  <Grid.Column width={5}>
                    <label className={styles.boldText}>{localize('VisitingAddress')}</label>
                  </Grid.Column>
                  <Grid.Column tablet={16} computer={11}>
                    <Grid.Row>
                      <Label className={styles.labelStyle} basic size="large">
                        {data.address.addressPart1}
                      </Label>
                    </Grid.Row>
                    <br />
                    <Grid.Row>
                      <Label className={styles.labelStyle} basic size="large">
                        {data.address.addressPart2}
                      </Label>
                    </Grid.Row>
                    <br />
                    <Grid.Row>
                      <Label className={styles.labelStyle} basic size="large">
                        {data.address.addressPart3}
                      </Label>
                    </Grid.Row>
                    <br />
                    <Grid.Row>
                      <Label className={styles.labelStyle} basic size="large">
                        {data.address.gpsCoordinates}
                      </Label>
                    </Grid.Row>
                  </Grid.Column>
                </Grid.Row>
              </Grid>
            </Grid.Column>

            <Grid.Column width={8}>
              <Grid doubling>
                <Grid.Row>
                  <Grid.Column width={5}>
                    <label className={styles.boldText}>{localize('PostalAddress')}</label>
                  </Grid.Column>
                  <Grid.Column tablet={16} computer={11}>
                    <Grid.Row>
                      <Label className={styles.labelStyle} basic size="large">
                        {hasValue(data.actualAddress) && hasValue(data.actualAddress.addressPart1)
                          ? data.actualAddress.addressPart1
                          : ''}
                      </Label>
                    </Grid.Row>
                    <br />
                    <Grid.Row>
                      <Label className={styles.labelStyle} basic size="large">
                        {hasValue(data.actualAddress) && hasValue(data.actualAddress.addressPart2)
                          ? data.actualAddress.addressPart2
                          : ''}
                      </Label>
                    </Grid.Row>
                    <br />
                    <Grid.Row>
                      <Label className={styles.labelStyle} basic size="large">
                        {hasValue(data.actualAddress) && hasValue(data.actualAddress.addressPart3)
                          ? data.actualAddress.addressPart3
                          : ''}
                      </Label>
                    </Grid.Row>
                    <br />
                    <Grid.Row>
                      <Label className={styles.labelStyle} basic size="large">
                        {hasValue(data.actualAddress) && hasValue(data.actualAddress.addressPart4)
                          ? data.actualAddress.addressPart4
                          : ''}
                      </Label>
                    </Grid.Row>
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
            <Grid.Column width={1} />
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
          <Grid.Row columns={4}>
            <Grid.Column>
              <div className={styles.container}>
                <label className={styles.boldText}>{`${localize('RegionLvl')} 1`}</label>
                <Label className={styles.labelStyle} basic size="large">
                  {regionMenu1.value}
                </Label>
              </div>
            </Grid.Column>
            <Grid.Column>
              <div className={styles.container}>
                <label className={styles.boldText}>{`${localize('RegionLvl')} 2`}</label>
                <Label className={styles.labelStyle} basic size="large">
                  {regionMenu2.value}
                </Label>
              </div>
            </Grid.Column>
            <Grid.Column>
              <div className={styles.container}>
                <label className={styles.boldText}>{`${localize('RegionLvl')} 3`}</label>
                <Label className={styles.labelStyle} basic size="large">
                  {regionMenu3.value}
                </Label>
              </div>
            </Grid.Column>
            <Grid.Column>
              <div className={styles.container}>
                <label className={styles.boldText}>{`${localize('RegionLvl')} 4`}</label>
                <Label className={styles.labelStyle} basic size="large">
                  {regionMenu4.value}
                </Label>
              </div>
            </Grid.Column>
          </Grid.Row>
          <br />
          <Grid.Row>
            <Grid.Column width={8}>
              <label className={styles.boldText}>{localize('PersonsRelatedToTheUnit')}</label>
              <PersonsGrid name="persons" value={data.persons} localize={localize} readOnly />
            </Grid.Column>
          </Grid.Row>
        </Grid>
      </div>
    )
  }
}

export default ContactInfo
