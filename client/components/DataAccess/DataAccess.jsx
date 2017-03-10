import React from 'react'
import { Loader, Accordion, Checkbox } from 'semantic-ui-react'


export default class DataAccess extends React.Component {
  constructor(props, context) {
    super(props, context)
  }
  createCheckbox = (item, type) => {
    const { onChange } = this.props
    const onChangeWrapCreator = (type, name) => e => {
      onChange({ type, name })
    }
    return (
      <div>
        <Checkbox
          name="hidden"
          label={item.name}
          key={item.name}
          onChange={onChangeWrapCreator(type, item.name)}
          checked={item.allowed} />
      </div>
    )
  }
  compare = (a, b) => {
      if (a.name < b.name)
        return -1;
      if (a.name > b.name)
        return 1;
      return 0;
    }
  render() {
    const { dataAccess, label } = this.props
    const panels = [
      {
        title: 'Legal unit',
        content: <div>{dataAccess.legalUnit.sort(this.compare).map(x => this.createCheckbox(x, 'legalUnit'))}</div>,
      },
      {
        title: 'Local unit',
        content: <div>{dataAccess.localUnit.sort(this.compare).map(x => this.createCheckbox(x, 'localUnit'))}</div>,
      },
      {
        title: 'Enterprise unit',
        content: <div>{dataAccess.enterpriseUnit.sort(this.compare).map(x => this.createCheckbox(x, 'enterpriseUnit'))}</div>,
      },
      {
        title: 'Enterprise group',
        content: <div>{dataAccess.enterpriseGroup.sort(this.compare).map(x => this.createCheckbox(x, 'enterpriseGroup'))}</div>,
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
