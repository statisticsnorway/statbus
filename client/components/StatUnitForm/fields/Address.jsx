import React from 'react'
import { Form, Message, Button, Icon, Segment, Dropdown } from 'semantic-ui-react'
import R from 'ramda'

import { internalRequest } from 'helpers/request'

const { arrayOf, func, shape, string } = React.PropTypes
const defaultCode = '41700000000000'

const defaultAddressState = {
  id: 0,
  addressPart1: '',
  addressPart2: '',
  addressPart3: '',
  addressPart4: '',
  addressPart5: '',
  region: { code: '', name: '' },
  gpsCoordinates: '',
}

class Address extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    onChange: func.isRequired,
    name: string.isRequired,
    errors: arrayOf(string),
    data: shape(),
  }

  static defaultProps = {
    data: null,
    errors: [],
  }

  state = {
    data: this.props.data || defaultAddressState,
    regionMenu1: { options: [], value: '', submenu: 'regionMenu2', substrRule: { start: 3, end: 5 } },
    regionMenu2: { options: [], value: '', submenu: 'regionMenu3', substrRule: { start: 5, end: 8 } },
    regionMenu3: { options: [], value: '', submenu: 'regionMenu4', substrRule: { start: 8, end: 11 } },
    regionMenu4: { options: [], value: '', submenu: null, substrRule: { start: 11, end: 14 } },
    msgFailFetchRegions: undefined,
    msgFailFetchRegionsByCode: undefined,
    msgFailFetchAddress: undefined,
    editing: false,
  }
  componentDidMount() {
    const { code } = this.state.data.region
    const menu = 'regionMenu'
    if (code) {
      for (let i = 1; i <= 4; i++) {
        const substrStart = this.state[`${menu}${i}`].substrRule.start
        const substrEnd = this.state[`${menu}${i}`].substrRule.end
        this.fetchByPartCode(`${menu}${i}`, code.substr(0, substrStart), defaultCode.substr(substrEnd),
        `${code.substr(0, substrEnd)}${defaultCode.substr(substrEnd)}`)
      }
    } else {
      const { substrRule: { start, end } } = this.state.regionMenu1
      this.fetchByPartCode(`${menu}1`, defaultCode.substr(0, start), defaultCode.substr(end), '0')
      for (let i = 2; i <= 4; i++) {
        this.resetMenu(`${menu}${i}`)
      }
    }
  }
  componentWillReceiveProps(newProps) {
    const newData = newProps.data || defaultAddressState
    if (!R.equals(this.state.data, newData)) {
      this.setState({ data: newData })
    }
  }

  defaultMenuItem = () => [{
    key: Math.random(),
    value: '0',
    text: this.props.localize('SelectRegion'),
  }]

  resetMenu = (name) => {
    this.setState(s => ({
      [name]: { ...s[name], options: this.defaultMenuItem(), value: '0' },
    }))
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  undoSelect = (name) => {
    let code
    switch (name) {
      case 'regionMenu2':
        code = this.state.regionMenu1.value
        break
      case 'regionMenu3':
        code = this.state.regionMenu2.value
        break
      case 'regionMenu4':
        code = this.state.regionMenu3.value
        break
      default:
        code = ''
    }
    return code
  }

  handleSelect = (_, { name, value }) => {
    if (value !== this.state[name].value) {
      const { submenu } = this.state[name]
      if (submenu) {
        const { substrRule: { start, end } } = this.state[submenu]
        let toReset = this.state[submenu].submenu
        while (toReset) {
          this.resetMenu(toReset)
          toReset = this.state[toReset].submenu
        }
        this.fetchByPartCode(submenu, value.substr(0, start), defaultCode.substr(end), '0')
      }
      this.setState(s => ({
        [name]: { ...s[name], value },
        data: { ...s.data, region: { ...s.data.region, code: value === '0' ? this.undoSelect(name) : value } },
      }))
    }
  }

  fetchByPartCode = (name, start, end, value) => internalRequest({
    url: '/api/regions/getAreasList',
    queryParams: { start, end },
    method: 'get',
    onSuccess: (result) => {
      this.setState(s => ({
        [name]: {
          ...s[name],
          options: this.defaultMenuItem().concat(
            result.map(x => ({ key: Math.random(), value: x.code, text: x.name }))),
          value,
        },
      }))
    },
    onFail: () => {
      this.setState({
        [name]: {
          options: [{ text: 'ERROR', value: 'error' }],
          value: 'error',
        },
      })
    },
  })

  startEditing = () => {
    this.setState({ editing: true })
  }

  doneEditing = (e) => {
    e.preventDefault()
    const { onChange, name: fieldName } = this.props
    onChange({ name: fieldName, value: this.state.data })
    this.setState({ editing: false })
  }

  cancelEditing = (e) => {
    e.preventDefault()
    const { onChange, name: fieldName, data } = this.props
    onChange({ name: fieldName, value: data })
    this.setState({ editing: false })
  }

  render() {
    const { localize, name, errors } = this.props
    const {
      data, msgFailFetchRegions,
      msgFailFetchRegionsByCode, editing,
      msgFailFetchAddress, regionMenu1, regionMenu2,
      regionMenu3, regionMenu4,
    } = this.state
    const attrs = editing ? { required: true } : { disabled: true }
    const label = localize(name)
    return (
      <Segment.Group as={Form.Field}>
        <Segment>{label}</Segment>
        <Segment.Group>
          <Segment>
            <Form.Group widths="equal">
              <Form.Input
                control={Dropdown}
                name="regionMenu1"
                label={`${localize('RegionPart')} 1`}
                options={regionMenu1.options}
                value={regionMenu1.value}
                onChange={this.handleSelect}
                {...attrs}
              />
              <Form.Input
                control={Dropdown}
                name="regionMenu2"
                label={`${localize('RegionPart')} 2`}
                options={regionMenu2.options}
                value={regionMenu2.value}
                onChange={this.handleSelect}
                disabled={!editing}
              />
              <Form.Input
                control={Dropdown}
                name="regionMenu3"
                label={`${localize('RegionPart')} 3`}
                options={regionMenu3.options}
                value={regionMenu3.value}
                onChange={this.handleSelect}
                disabled={!editing}
              />
              <Form.Input
                control={Dropdown}
                name="regionMenu4"
                label={`${localize('RegionPart')} 4`}
                options={regionMenu4.options}
                value={regionMenu4.value}
                onChange={this.handleSelect}
                disabled={!editing}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart1"
                value={data.addressPart1}
                label={`${localize('AddressPart')} 1`}
                placeholder={`${localize('AddressPart')} 1`}
                onChange={this.handleEdit}
                {...attrs}
              />
              <Form.Input
                name="addressPart2"
                value={data.addressPart2}
                label={`${localize('AddressPart')} 2`}
                placeholder={`${localize('AddressPart')} 2`}
                onChange={this.handleEdit}
                {...attrs}
              />
              <Form.Input
                name="addressPart3"
                value={data.addressPart3}
                label={`${localize('AddressPart')} 3`}
                placeholder={`${localize('AddressPart')} 3`}
                onChange={this.handleEdit}
                {...attrs}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart4"
                value={data.addressPart4}
                label={`${localize('AddressPart')} 4`}
                placeholder={`${localize('AddressPart')} 4`}
                onChange={this.handleEdit}
                disabled={!editing}
              />
              <Form.Input
                name="addressPart5"
                value={data.addressPart5}
                label={`${localize('AddressPart')} 5`}
                placeholder={`${localize('AddressPart')} 5`}
                onChange={this.handleEdit}
                disabled={!editing}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                control={Message}
                name="RegionCode"
                label={localize('RegionCode')}
                info
                size="mini"
                header={data.region.code || localize('RegionCode')}
                disabled={!editing}
              />
              <Form.Input
                name="gpsCoordinates"
                value={data.gpsCoordinates}
                onChange={this.handleEdit}
                label={localize('GpsCoordinates')}
                placeholder={localize('GpsCoordinates')}
                disabled={!editing}
              />
            </Form.Group>
          </Segment>
          <Segment clearing>
            {editing ?
              <Button.Group floated="right">
                <Button
                  type="button"
                  icon={<Icon name="check" />}
                  onClick={this.doneEditing}
                  color="green"
                  size="small"
                  disabled={!data.region.code ||
                    !(data.addressPart1 && data.addressPart2 && data.addressPart3)
                  }
                />
                <Button
                  type="button"
                  icon={<Icon name="cancel" />}
                  onClick={this.cancelEditing}
                  color="red"
                  size="small"
                />
              </Button.Group> :
              <Button.Group floated="right">
                <Button
                  type="button"
                  icon={<Icon name="edit" />}
                  onClick={this.startEditing}
                  color="blue"
                  size="small"
                />
              </Button.Group>}
          </Segment>
        </Segment.Group>
        {msgFailFetchRegions && <Message error content={msgFailFetchRegions} />}
        {msgFailFetchRegionsByCode && <Message error content={msgFailFetchRegionsByCode} />}
        {msgFailFetchAddress && <Message error content={msgFailFetchAddress} />}
        {errors.length !== 0 && <Message error title={label} list={errors.map(localize)} />}
      </Segment.Group>
    )
  }
}

export default Address
