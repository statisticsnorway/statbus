import React from 'react'
import { arrayOf, func, shape, string } from 'prop-types'
import { Grid, Label, Header, Segment, Message } from 'semantic-ui-react'
import R from 'ramda'
import { groupByToArray } from 'helpers/enumerable'

import ListWithDnd from 'components/ListWithDnd'
import { hasValue } from 'helpers/validation'
import colors from 'helpers/colors'
import Item from './Item'
import { tryFieldIsRequired, tryFieldIsRequiredForUpdate } from '../model'
import styles from './styles.pcss'

const resetSelection = ({ hovered }) => ({
  left: undefined,
  right: undefined,
  dragStarted: false,
  hovered,
})

const multipleAssignmentVariables = []

class MappingsEditor extends React.Component {
  static propTypes = {
    attributes: arrayOf(string).isRequired,
    columns: arrayOf(shape({
      name: string.isRequired,
      localizeKey: string.isRequired,
    }).isRequired).isRequired,
    value: arrayOf(arrayOf(string.isRequired).isRequired),
    mandatoryColumns: arrayOf(string),
    onChange: func.isRequired,
    localize: func.isRequired,
    mapping: shape({}).isRequired,
    attribs: shape({}).isRequired,
  }

  static defaultProps = {
    value: [],
    mandatoryColumns: [],
  }

  state = {
    left: undefined,
    right: undefined,
    dragStarted: false,
    hovered: undefined,
  }

  componentWillReceiveProps(nextProps) {
    const newAttrib =
      this.state.left !== undefined &&
      nextProps.attributes.find(attr => attr === this.state.left) === undefined
    const newColumn =
      this.state.right !== undefined &&
      nextProps.columns.find(col => col.name === this.state.right) === undefined
    if (newAttrib || newColumn) this.setState(resetSelection)
  }

  getOther(prop) {
    return prop === 'left' ? this.state.right : this.state.left
  }

  getAttributeColor(prop, value) {
    const leftIndex = this.props.attributes.indexOf(prop === 'left' ? value : this.props.value.find(([, col]) => col === value)[0])
    return colors[(leftIndex + 1) % colors.length]
  }

  mouseUpIsBeingTracked(prop) {
    return this.state.dragStarted && this.getOther(prop)
  }

  handleAdd(prop, value) {
    const pair = prop === 'left' ? [value, this.state.right] : [this.state.left, value]
    const duplicate = this.props.value.find(m => m[0] === pair[0] && m[1] === pair[1])
    if (duplicate === undefined) {
      const nextValue = multipleAssignmentVariables.includes(pair[1])
        ? this.props.value.concat([pair])
        : this.props.value.filter(m => m[1] !== pair[1]).concat([pair])
      this.setState(resetSelection, () => {
        this.props.onChange(nextValue)
      })
    } else {
      this.setState(resetSelection)
    }
  }

  handleMouseDown = (prop, value) => (e) => {
    e.preventDefault()
    this.setState({
      right: undefined,
      left: undefined,
      [prop]: value,
      dragStarted: true,
    })
  }

  handleMouseUp = (prop, value) => (e) => {
    e.preventDefault()
    document.removeEventListener('mouseup', this.handleMouseUpOutside, false)
    if (this.mouseUpIsBeingTracked(prop)) this.handleAdd(prop, value)
    else this.setState(resetSelection)
  }

  handleMouseUpOutside = () => {
    this.setState(resetSelection)
  }

  // eslint-disable-next-line class-methods-use-this
  functionTryFieldIsRequired(cols: Array, field: string, variablesMapping) {
    return tryFieldIsRequired(cols.map(x => x.name), field.split('.')[0], variablesMapping)
  }

  handleMouseEnter = (prop, value) => () => {
    this.setState({ hovered: { [prop]: value } }, () => {
      if (this.mouseUpIsBeingTracked(prop)) {
        document.removeEventListener('mouseup', this.handleMouseUpOutside, false)
      }
    })
  }

  handleMouseLeave = () => {
    if (this.state.dragStarted) {
      document.addEventListener('mouseup', this.handleMouseUpOutside, false)
    }
    this.setState({ hovered: undefined })
  }

  handleClick = (prop, value) => () => {
    if (!this.state[prop]) this.setState({ [prop]: value })
    else if (this.getOther(prop)) this.handleAdd(prop, value)
  }

  renderItem(prop, value, label) {
    // console.log(props.isUpdate);

    const isRequired = typeof label === 'string' && label.includes('*')
    const adopt = f => f(prop, value)
    const index = this.props.value.findIndex(x => x[prop === 'left' ? 0 : 1] === value)
    const { hovered } = this.state
    return (
      <Item
        key={value}
        id={`${prop}_${value}`}
        text={label || value}
        selected={this.state[prop] === value}
        onClick={adopt(this.handleClick)}
        onMouseDown={adopt(this.handleMouseDown)}
        onMouseUp={adopt(this.handleMouseUp)}
        onMouseEnter={adopt(this.handleMouseEnter)}
        onMouseLeave={this.handleMouseLeave}
        hovered={hovered !== undefined && hovered[prop] === value}
        pointing={index >= 0 ? (prop === 'left' ? 'right' : 'left') : prop}
        isRequired={this.tryFieldIsRequiredForUpdate(this.props.mapping.value) ? false : isRequired}
        color={
          prop === 'left' || index >= 0
            ? this.getAttributeColor(prop, value)
            : isRequired &&
              this.functionTryFieldIsRequired(this.props.columns, value, this.props.mapping.value)
            ? 'red'
            : 'grey'
        }
      />
    )
  }

  render() {
    const {
      attributes,
      columns,
      value: mappings,
      mandatoryColumns: mandatoryCols,
      onChange,
      localize,
      mapping,
      attribs,
      isUpdate,
    } = this.props

    // console.log(this.props);

    // console.log(attributes);
    // console.log(mandatoryCols);

    // const isUpdate =

    const labelColumn = key =>
      key && key.includes('.')
        ? key
          .split('.')
          .map((x, i) =>
            i === 0 && (mandatoryCols.includes(x) || mandatoryCols.includes(key))
              ? `${localize(x)}*`
              : localize(x))
          .join(' > ')
        : mandatoryCols.includes(key)
          ? `${localize(key)}*`
          : localize(key)
    const renderValueItem = ([attr, col]) => {
      const color = this.getAttributeColor('left', attr)
      const column = columns.find(c => c.name === col)
      const colText = labelColumn(column && column.localizeKey)
      const onRemove = () => onChange(R.without([[attr, col]], mappings))
      return (
        <Label.Group>
          <Label content={attr} pointing="right" color={color} basic />
          <Label content={colText} onRemove={onRemove} pointing="left" color={color} basic />
        </Label.Group>
      )
    }
    const filteredMappings = mappings.filter(x => columns.some(col => col.name === x[1]))
    const grouppedColumns = groupByToArray(columns, x => x.groupNumber)
    return (
      <Grid>
        <Grid.Row>
          <Grid.Column width={5}>
            <Header content={localize('VariablesOfDataSource')} as="h5" />
            <Segment>{attributes.map(x => this.renderItem('left', x))}</Segment>
          </Grid.Column>
          <Grid.Column width={11}>
            <Header content={localize('VariablesOfDatabase')} as="h5" />
            <Segment>
              {grouppedColumns.map(group => (
                <div>
                  {group.value.map(x =>
                    this.renderItem('right', x.name, labelColumn(x.localizeKey)))}
                </div>
              ))}
            </Segment>
          </Grid.Column>
        </Grid.Row>
        <Grid.Row>
          <Grid.Column width={5} floated="left">
            <br />
            {mapping.touched && hasValue(mapping.errors) && (
              <Message title={localize(mapping.label)} list={mapping.errors.map(localize)} error />
            )}
            {attribs.touched && hasValue(attribs.errors) && (
              <Message title={localize(attribs.label)} list={attribs.errors.map(localize)} error />
            )}
          </Grid.Column>
          <Grid.Column width={11} textAlign="center" floated="right">
            <Header content={localize('VariablesMappingResults')} as="h5" />
            <Segment>
              <ListWithDnd
                value={filteredMappings}
                onChange={onChange}
                renderItem={renderValueItem}
                getItemKey={R.join('-')}
                listProps={{ className: styles['values-root'] }}
                listItemProps={{ className: styles['mappings-item'] }}
              />
            </Segment>
          </Grid.Column>
        </Grid.Row>
      </Grid>
    )
  }
}

export default MappingsEditor
