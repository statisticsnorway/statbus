import React from 'react'
import { Form, Search, Message, Button, Icon, Segment } from 'semantic-ui-react'
import { internalRequest } from 'helpers/request'
import { wrapper } from 'helpers/locale'
import debounce from 'lodash/debounce'

const { func, shape, string } = React.PropTypes
const waitTime = 500
class Address extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    onChange: func.isRequired,
    name: string.isRequired,
    data: shape(),
  }

  state = {
    data: this.props.data ?
    this.props.data :
    {
      id: 0,
      addressPart1: '',
      addressPart2: '',
      addressPart3: '',
      addressPart4: '',
      addressPart5: '',
      addressDetails: '',
      geographicalCodes: '',
      gpsCoordinates: '',
    },
    isSoateLoading: false,
    isAddressDetailsLoading: false,
    soateResults: [],
    addressResults: [],
    msgFailFetchSoates: undefined,
    msgFailFetchSoatesByCode: undefined,
    msgFailFetchAddress: undefined,
    editing: false,
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  handleSoateEdit = (e, value) => {
    this.setState(s => ({ data: { ...s.data, geographicalCodes: value }, isSoateLoading: true }))
    debounce(() => internalRequest({
      url: '/api/soates',
      queryParams: { code: value, limit: 5 },
      method: 'get',
      onSuccess: (result) => {
        this.setState(s => ({ data: { ...s.data },
          isSoateLoading: false,
          msgFailFetchSoatesByCode: undefined,
          soateResults: [...result.map(x => ({ title: x.code, description: x.name }))],
        }))
      },
      onFail: () => {
        this.setState(s => ({ data:
          { ...s.data },
          isSoateLoading: false,
          soateResults: [],
          msgFailFetchSoatesByCode: 'Failed to fetch Soate Structure' }
          ))
      },
    }), waitTime)()
  }

  handleSoateSearchResultSelect = (e, soate) => {
    e.preventDefault()
    internalRequest({
      url: `/api/soates/${soate.title}`,
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
          msgFailFetchSoates: undefined,
          isSoateLoading: false,
        }))
      },
      onFail: () => {
        this.setState(s => ({ data:
          { ...s.data },
          isSoateLoading: false,
          msgFailFetchSoates: 'Failed to fetch Soate' }
          ))
      },
    })
    this.setState(s => ({ data: { ...s.data, geographicalCodes: soate.title } }))
  }

  handleAddressDetailsEdit = (e, value) => {
    this.setState(s => (
      { data:
        { ...s.data, addressDetails: value },
        isAddressDetailsLoading: true,
      }))
    debounce(() => (internalRequest({
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
    })), waitTime)()
  }

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

  doneEditing = () => {
    const { onChange, name: fieldName } = this.props
    onChange(null, { name: fieldName, value: this.state.data })
    this.setState({ editing: false })
  }

  render() {
    const { localize, name } = this.props
    const {
      data, isSoateLoading, soateResults, msgFailFetchSoates,
      msgFailFetchSoatesByCode, editing, isAddressDetailsLoading,
      addressResults, msgFailFetchAddress,
    } = this.state
    const attrs = editing ? { required: true } : { disabled: true }
    return (
      <Segment.Group as={Form.Field}>
        <Segment>{localize(name)}</Segment>
        <Segment.Group>
          <Segment>
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart1" value={data.addressPart1} label={`${localize('AddressPart')} 1`}
                placeholder={`${localize('AddressPart')} 1`} disabled
              />
              <Form.Input
                name="addressPart2" value={data.addressPart2} label={`${localize('AddressPart')} 2`}
                placeholder={`${localize('AddressPart')} 2`} disabled
              />
              <Form.Input
                name="addressPart3" value={data.addressPart3} label={`${localize('AddressPart')} 3`}
                placeholder={`${localize('AddressPart')} 3`} disabled
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart4" value={data.addressPart4} label={`${localize('AddressPart')} 4`}
                placeholder={`${localize('AddressPart')} 4`} disabled
              />
              <Form.Input
                name="addressPart5" value={data.addressPart5} label={`${localize('AddressPart')} 5`}
                placeholder={`${localize('AddressPart')} 5`} disabled
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Field
                label={localize('GeographicalCodes')} control={Search} loading={isSoateLoading}
                placeholder={localize('GeographicalCodes')} fluid
                onResultSelect={this.handleSoateSearchResultSelect}
                onSearchChange={this.handleSoateEdit} results={soateResults}
                value={data.geographicalCodes} {...attrs}
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
              {...attrs}
            />
          </Segment>
          <Segment clearing>
            {editing ?
              <Button
                type="button" floated="right" icon={<Icon name="check" />}
                onClick={this.doneEditing} color="green" size="small"
              /> :
              <Button
                type="button" floated="right" icon={<Icon name="edit" />}
                onClick={this.startEditing} color="orange" size="small"
              />}
          </Segment>
        </Segment.Group>
        {msgFailFetchSoates && <Message content={msgFailFetchSoates} negative />}
        {msgFailFetchSoatesByCode && <Message content={msgFailFetchSoatesByCode} negative />}
        {msgFailFetchAddress && <Message content={msgFailFetchAddress} negative />}
      </Segment.Group>)
  }
}

export default wrapper(Address)
