import React from 'react'
import { Form, Search, Message, Button, Icon, Segment } from 'semantic-ui-react'
import debounce from 'lodash/debounce'
import R from 'ramda'

import { internalRequest } from 'helpers/request'

const { arrayOf, func, shape, string } = React.PropTypes
const waitTime = 250

const defaultAddressState = {
  id: 0,
  addressPart1: '',
  addressPart2: '',
  addressPart3: '',
  addressPart4: '',
  addressPart5: '',
  addressDetails: '',
  geographicalCodes: '',
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
    isRegionLoading: false,
    isAddressDetailsLoading: false,
    regionResults: [],
    addressResults: [],
    msgFailFetchRegions: undefined,
    msgFailFetchRegionsByCode: undefined,
    msgFailFetchAddress: undefined,
    editing: false,
  }

  componentWillReceiveProps(newProps) {
    const newData = newProps.data || defaultAddressState
    if (!R.equals(this.state.data, newData)) {
      this.setState({ data: newData })
    }
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  handleRegionEdit = (e, value) => {
    this.setState(
      s => ({ data: { ...s.data, geographicalCodes: value }, isRegionLoading: true }),
      () => {
        this.searchRegion({ code: value, limit: 5 })
      },
    )
  }

  searchRegion = debounce(params => internalRequest({
    url: '/api/regions/search',
    queryParams: params,
    method: 'get',
    onSuccess: (result) => {
      this.setState(s => ({ data: { ...s.data },
        isRegionLoading: false,
        msgFailFetchRegionsByCode: undefined,
        regionResults: [...result.map(x => ({ title: x.code, description: x.name }))],
      }))
    },
    onFail: () => {
      this.setState(s => ({ data:
        { ...s.data },
        isRegionLoading: false,
        regionResults: [],
        msgFailFetchRegionsByCode: 'Failed to fetch Region Structure' }
        ))
    },
  }), waitTime)

  handleRegionSearchResultSelect = (e, region) => {
    e.preventDefault()
    internalRequest({
      url: `/api/regions/${region.title}`,
      method: 'get',
      onSuccess: (result) => {
        const [addressPart1 = '', addressPart2 = '', addressPart3 = '', addressPart4 = '', addressPart5 = ''] = result
        this.setState(s => ({ data: {
          ...s.data,
          addressPart1,
          addressPart2,
          addressPart3,
          addressPart4,
          addressPart5 },
          msgFailFetchRegions: undefined,
          isRegionLoading: false,
        }))
      },
      onFail: () => {
        this.setState(s => ({ data:
          { ...s.data },
          isRegionLoading: false,
          msgFailFetchRegions: 'Failed to fetch Region' }
          ))
      },
    })
    this.setState(s => ({ data: { ...s.data, geographicalCodes: region.title } }))
  }

  handleAddressDetailsEdit = (e, value) => {
    this.setState(s => (
      {
        data: { ...s.data, addressDetails: value },
        isAddressDetailsLoading: true,
      }
    ), () => {
      this.addressDetailsSearch(value)
    })
  }

  addressDetailsSearch = debounce(value => internalRequest({
    url: '/api/addresses',
    queryParams: { searchStr: value },
    method: 'get',
    onSuccess: ({ addresses }) => {
      this.setState(s => ({ data: { ...s.data },
        isAddressDetailsLoading: false,
        msgFailFetchAddress: undefined,
        addressResults: [...addresses.map(x => (
          { title: x.addressDetails, description: x.gpsCoordinates, ...x }))],
      }))
    },
    onFail: () => {
      this.setState(s => ({ data:
        { ...s.data },
        isAddressDetailsLoading: false,
        addressResults: [],
        msgFailFetchAddress: 'Failed to fetch Address list by search value' }
        ))
    },
  }), waitTime)

  handleAddressDetailsSearchResultSelect = (e, address) => {
    e.preventDefault()
    this.setState({ data: {
      addressPart1: address.addressPart1,
      addressPart2: address.addressPart2,
      addressPart3: address.addressPart3,
      addressPart4: address.addressPart4,
      addressPart5: address.addressPart5,
      addressDetails: address.addressDetails,
      geographicalCodes: address.geographicalCodes,
      gpsCoordinates: address.gpsCoordinates,
      id: address.id,
    } })
  }

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
      data, isRegionLoading, regionResults, msgFailFetchRegions,
      msgFailFetchRegionsByCode, editing, isAddressDetailsLoading,
      addressResults, msgFailFetchAddress,
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
                name="addressPart1" value={data.addressPart1} label={`${localize('AddressPart')} 1`}
                placeholder={`${localize('AddressPart')} 1`} disabled readOnly
              />
              <Form.Input
                name="addressPart2" value={data.addressPart2} label={`${localize('AddressPart')} 2`}
                placeholder={`${localize('AddressPart')} 2`} disabled readOnly
              />
              <Form.Input
                name="addressPart3" value={data.addressPart3} label={`${localize('AddressPart')} 3`}
                placeholder={`${localize('AddressPart')} 3`} disabled readOnly
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart4" value={data.addressPart4} label={`${localize('AddressPart')} 4`}
                placeholder={`${localize('AddressPart')} 4`} disabled readOnly
              />
              <Form.Input
                name="addressPart5" value={data.addressPart5} label={`${localize('AddressPart')} 5`}
                placeholder={`${localize('AddressPart')} 5`} disabled readOnly
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Field
                label={localize('GeographicalCodes')} control={Search} loading={isRegionLoading}
                placeholder={localize('GeographicalCodes')} fluid
                onResultSelect={this.handleRegionSearchResultSelect}
                onSearchChange={this.handleRegionEdit} results={regionResults}
                showNoResults={false} value={data.geographicalCodes} {...attrs}
              />
              <Form.Input
                name="gpsCoordinates" value={data.gpsCoordinates}
                onChange={this.handleEdit} label={localize('GpsCoordinates')}
                placeholder={localize('GpsCoordinates')} disabled={!editing}
              />
            </Form.Group>
            <Form.Field
              label={localize('AddressDetails')} value={data.addressDetails}
              placeholder={localize('AddressDetails')} control={Search}
              loading={isAddressDetailsLoading} fluid
              onResultSelect={this.handleAddressDetailsSearchResultSelect}
              onSearchChange={this.handleAddressDetailsEdit} results={addressResults}
              showNoResults={false} {...attrs}
            />
          </Segment>
          <Segment clearing>
            {editing ?
              <Button.Group floated="right">
                <Button
                  type="button" icon={<Icon name="check" />}
                  onClick={this.doneEditing} color="green" size="small"
                  disabled={!(data.addressDetails && data.geographicalCodes)}
                />
                <Button
                  type="button" icon={<Icon name="cancel" />}
                  onClick={this.cancelEditing} color="red" size="small"
                />
              </Button.Group> :
              <Button.Group floated="right">
                <Button
                  type="button" icon={<Icon name="edit" />}
                  onClick={this.startEditing} color="blue" size="small"
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
