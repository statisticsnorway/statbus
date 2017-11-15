import React from 'react'
import { Form, Message } from 'semantic-ui-react'
import { arrayOf, func, shape, string, bool } from 'prop-types'
import { equals } from 'ramda'

import { internalRequest } from 'helpers/request'

const defaultCode = '41700000000000'

const defaultRegionState = {
  region: { code: '', name: '' },
}

class RegionField extends React.Component {
  static propTypes = {
    name: string.isRequired,
    data: shape(),
    editing: bool.isRequired,
    errors: arrayOf(string),
    disabled: bool,
    onRegionSelected: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    data: null,
    errors: [],
    disabled: false,
    editing: false,
  }

  state = {
    data: { region: { ...this.props.data } } || defaultRegionState,
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
    msgFailFetchRegions: undefined,
    msgFailFetchRegionsByCode: undefined,
    editing: this.props.editing,
  }

  componentDidMount() {
    const code = this.state.data.region !== null ? this.state.data.region.code : null
    const menu = 'regionMenu'
    if (code) {
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
    } else {
      const { substrRule: { start, end } } = this.state.regionMenu1
      this.fetchByPartCode(`${menu}1`, defaultCode.substr(0, start), defaultCode.substr(end), '0')
      for (let i = 2; i <= 4; i++) {
        this.resetMenu(`${menu}${i}`)
      }
    }
  }

  componentWillReceiveProps(newProps) {
    const newEditing = newProps.editing
    if (!equals(this.state.editing, newEditing)) {
      this.setState({ editing: newEditing })
    }
  }

  resetMenu = (name) => {
    this.setState(s => ({
      [name]: { ...s[name], options: [], value: '0' },
    }))
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
      this.setState(
        s => ({
          [name]: { ...s[name], value },
          data: {
            ...s.data,
            region: { ...s.data.region, code: value === '0' ? this.undoSelect(name) : value },
          },
        }),
        () => {
          this.props.onRegionSelected(this.state.data.region)
        },
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
    const { localize, name, errors: errorKeys, disabled } = this.props
    const {
      msgFailFetchRegions,
      msgFailFetchRegionsByCode,
      editing,
      regionMenu1,
      regionMenu2,
      regionMenu3,
      regionMenu4,
    } = this.state
    const defaultMenuItem = {
      key: '0',
      value: '0',
      text: localize('SelectRegion'),
    }
    const attrs = editing ? { required: true } : { disabled: true }
    if (editing && disabled) attrs.disabled = true
    const label = localize(name)
    return (
      <div>
        <Form.Group widths="equal">
          <Form.Select
            name="regionMenu1"
            label={`${localize('RegionPart')} 1`}
            options={[defaultMenuItem, ...regionMenu1.options]}
            value={regionMenu1.value}
            onChange={this.handleSelect}
            {...attrs}
          />
          <Form.Select
            name="regionMenu2"
            label={`${localize('RegionPart')} 2`}
            options={[defaultMenuItem, ...regionMenu2.options]}
            value={regionMenu2.value}
            onChange={this.handleSelect}
            disabled={disabled || !editing || regionMenu2.options.length === 0}
          />
        </Form.Group>
        <Form.Group widths="equal">
          <Form.Select
            name="regionMenu3"
            label={`${localize('RegionPart')} 3`}
            options={[defaultMenuItem, ...regionMenu3.options]}
            value={regionMenu3.value}
            onChange={this.handleSelect}
            disabled={disabled || !editing || regionMenu3.options.length === 0}
          />
          <Form.Select
            name="regionMenu4"
            label={`${localize('RegionPart')} 4`}
            options={[defaultMenuItem, ...regionMenu4.options]}
            value={regionMenu4.value}
            onChange={this.handleSelect}
            disabled={disabled || !editing || regionMenu4.options.length === 0}
          />
        </Form.Group>
        {msgFailFetchRegions && <Message content={msgFailFetchRegions} error />}
        {msgFailFetchRegionsByCode && <Message content={msgFailFetchRegionsByCode} error />}
        {errorKeys.length !== 0 && <Message title={label} list={errorKeys.map(localize)} error />}
      </div>
    )
  }
}

export default RegionField
