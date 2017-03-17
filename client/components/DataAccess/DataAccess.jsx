import React from 'react'
import { Accordion, Checkbox } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const { func, string, arrayOf, shape, bool } = React.PropTypes
const validUnit = arrayOf(shape({
  name: string.isRequired,
  allowed: bool.isRequired })
  .isRequired)
  .isRequired
class DataAccess extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    label: string.isRequired,
    value: shape({
      legalUnit: validUnit,
      localUnit: validUnit,
      enterpriseUnit: validUnit,
      enterpriseGroup: validUnit,
    }).isRequired,
    onChange: func.isRequired,
  }

  createCheckbox = (item, type) => {
    const onChangeWrapCreator = name => () => {
      this.props.onChange({ type, name })
    }
    return (
      <div key={item.name}>
        <Checkbox
          name="hidden"
          label={item.name}
          onChange={onChangeWrapCreator(item.name)}
          checked={item.allowed}
        />
      </div>
    )
  }

  compare = (a, b) => {
    if (a.name < b.name) return -1
    if (a.name > b.name) return 1
    return 0
  }

  render() {
    const { value, label, localize } = this.props
    const panels = [
      {
        title: localize('LegalUnit'),
        content: <div>{value.legalUnit.sort(this.compare).map(x => this.createCheckbox(x, 'legalUnit'))}</div>,
      },
      {
        title: localize('LocalUnit'),
        content: <div>{value.localUnit.sort(this.compare).map(x => this.createCheckbox(x, 'localUnit'))}</div>,
      },
      {
        title: localize('EnterpriseUnit'),
        content: <div>{value.enterpriseUnit.sort(this.compare).map(x => this.createCheckbox(x, 'enterpriseUnit'))}</div>,
      },
      {
        title: localize('EnterpriseGroup'),
        content: <div>{value.enterpriseGroup.sort(this.compare).map(x => this.createCheckbox(x, 'enterpriseGroup'))}</div>,
      },
    ]
    return (
      <div className="field">
        <label>{label}</label>
        <Accordion panels={panels} styled />
      </div>
    )
  }
}
export default wrapper(DataAccess)
